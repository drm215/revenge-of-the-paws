import hashlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from http.server import BaseHTTPRequestHandler, HTTPServer

USER = {"id": "u1", "email": "a@b.co"}
USER_B = {"id": "u2", "email": "b@b.co"}
teams = {}  # id -> {code, state, version}
members = []  # {team_id, user_id, name, zip}
fail_next_save = [False]
chat = []  # {id, team_id, user_id, name, body, ping, created_at, t}
raids = []  # {id, team_id, host, territory, legend, seed, config, status, result, created_at}
raid_members = []  # {raid_id, user_id, name, pack, ready, t}
raid_actions = {}  # (raid_id, seq) -> {user_id, action}
RAID_FNS = ("team_raid", "open_raid", "join_raid", "leave_raid", "start_raid", "post_raid_action",
            "raid_actions_after", "finish_raid", "cancel_raid")
_n = [0]


def stamp():  # server-made timestamps, with a "+" that must survive the URL
    _n[0] += 1
    return "2026-11-01T00:00:%02d.123456+00:00" % _n[0]


state = {"hits": [], "password": "oldpass", "token": "tok-recovery", "recover": [], "saves": [], "refreshes": 0}
slow = {}  # POST /_slow: seconds to hold requests open ("save_team_state", "refresh"); "refresh_fails"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"null") if n else None

    def _send(self, code, data):
        b = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        if self.path.startswith("/rest/"):
            self.send_header("Content-Encoding", "gzip")  # as a browser hands it over: already unpacked
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _authed(self):
        return self.headers.get("Authorization", "") == "Bearer " + state["token"]

    def _user(self):
        auth = self.headers.get("Authorization", "")
        return "u1" if auth == "Bearer " + state["token"] else ("u2" if auth == "Bearer tok-b" else None)

    def _team_row(self, tid):
        t = teams[tid]
        return dict(t, id=tid, members=[{"user_id": x["user_id"], "name": x["name"], "zip": x["zip"]}
                                        for x in members if x["team_id"] == tid])

    def _member(self, tid, uid):
        return any(m["team_id"] == tid and m["user_id"] == uid for m in members)

    def _team_of(self, uid, tid=None):
        """The team `tid` if `uid` is on it (one team per saved game)."""
        if tid and tid in teams and self._member(tid, uid):
            return self._team_row(tid)
        return None

    def _raid_row(self, r):
        ms = sorted((m for m in raid_members if m["raid_id"] == r["id"]), key=lambda m: m["t"])
        out = {k: v for k, v in r.items()}
        out["members"] = [{"user_id": m["user_id"], "name": m["name"], "pack": m["pack"], "ready": m["ready"]} for m in ms]
        return out

    def _pulse(self, body):
        """Mirrors server/pulse.sql."""
        if slow.get("no_pulse"):
            return self._send(404, {"message": "Could not find the function"})
        uid = self._user()
        if uid is None:
            return self._send(401, {"message": "JWT invalid"})
        state["pulses"] = state.get("pulses", 0) + 1
        tid = body.get("p_team")
        team = self._team_of(uid, tid)
        if not team:
            return self._send(200, None)
        mine = [r for r in raids if r["team_id"] == tid and r["status"] != "cancelled"]
        raid = self._raid_row(mine[-1]) if mine else None
        team_tag = hashlib.md5(json.dumps(team, sort_keys=True).encode()).hexdigest()
        raid_tag = hashlib.md5(json.dumps(raid, sort_keys=True).encode()).hexdigest() if raid else ""
        send_team = team_tag != body.get("p_team_tag")
        send_raid = raid_tag != body.get("p_raid_tag")
        state["pulse_team_rows"] = state.get("pulse_team_rows", 0) + (1 if send_team else 0)
        state["pulse_raid_rows"] = state.get("pulse_raid_rows", 0) + (1 if send_raid and raid else 0)
        messages = [{k: v for k, v in m.items() if k not in ("t", "team_id")} for m in chat
                    if m["team_id"] == tid and m["id"] > body.get("p_after", 0)]
        return self._send(200, {"team_tag": team_tag, "team": team if send_team else None, "raid_tag": raid_tag,
                                "raid_changed": send_raid, "raid": raid if send_raid else None, "messages": messages[-100:]})

    def _raid_rpc(self, name, body):
        if name in ("team_raid",):
            state["old_polls"] = state.get("old_polls", 0) + 1
        uid = self._user()
        if uid is None:
            return self._send(401, {"message": "JWT invalid"})
        team = self._team_of(uid, body.get("p_team"))
        tid = team["id"] if team else None
        mine = [r for r in raids if r["team_id"] == tid and r["status"] != "cancelled"]
        latest = mine[-1] if mine else None
        active = latest if latest and latest["status"] in ("lobby", "fighting") else None
        member = lambda rid: any(m["raid_id"] == rid and m["user_id"] == uid for m in raid_members)
        err = lambda msg: self._send(400, {"message": msg})
        if name == "team_raid":
            return self._send(200, self._raid_row(latest) if latest else None)
        if name == "open_raid":
            if tid is None:
                return err("Join a team first.")
            if active:
                return err("Your team already has a raid going. Join it from the map.")
            r = {"id": "r%d" % (len(raids) + 1), "team_id": tid, "host": uid, "territory": body["p_territory"],
                 "legend": body["p_legend"], "seed": body["p_seed"], "config": "", "status": "lobby", "result": "",
                 "created_at": datetime.now(timezone.utc).isoformat()}
            raids.append(r)
            raid_members.append({"raid_id": r["id"], "user_id": uid, "name": body["p_name"], "pack": body["p_pack"],
                                 "ready": body["p_pack"] != "", "t": time.time()})
            return self._send(200, self._raid_row(r))
        if name == "join_raid":
            if not active or active["status"] != "lobby":
                return err("There is no raid to join right now.")
            ms = [m for m in raid_members if m["raid_id"] == active["id"]]
            me = next((m for m in ms if m["user_id"] == uid), None)
            if me is None and len(ms) >= 4:
                return err("The raid is full (4 players).")
            if me is None:
                me = {"raid_id": active["id"], "user_id": uid, "t": time.time()}
                raid_members.append(me)
            me.update(name=body["p_name"], pack=body["p_pack"], ready=body["p_ready"])
            return self._send(200, self._raid_row(active))
        if name == "cancel_raid":
            for r in raids:
                if r["id"] == body["p_raid"] and r["status"] in ("lobby", "fighting"):
                    r["status"] = "cancelled"
            return self._send(204, None)
        if name == "leave_raid":
            if active and active["status"] == "lobby":
                if active["host"] == uid:
                    active["status"] = "cancelled"
                else:
                    raid_members[:] = [m for m in raid_members if not (m["raid_id"] == active["id"] and m["user_id"] == uid)]
            return self._send(204, None)
        if name == "start_raid":
            if not active or active["status"] != "lobby":
                return err("There is no raid to start.")
            if active["host"] != uid:
                return err("Only the player who opened the raid can start it.")
            raid_members[:] = [m for m in raid_members if m["raid_id"] != active["id"] or m["ready"]]
            active.update(status="fighting", config=body["p_config"])
            return self._send(200, self._raid_row(active))
        rid = body.get("p_raid")
        if not member(rid):
            return err("You are not in this raid.")
        if name == "post_raid_action":
            key = (rid, body["p_seq"])
            raid_actions.setdefault(key, {"user_id": uid, "action": body["p_action"]})
            a = raid_actions[key]
            return self._send(200, {"seq": body["p_seq"], "user_id": a["user_id"], "action": a["action"]})
        if name == "raid_actions_after":
            rows = sorted((k[1], v) for k, v in raid_actions.items() if k[0] == rid and k[1] > body["p_after"])
            return self._send(200, [{"seq": q, "user_id": v["user_id"], "action": v["action"]} for q, v in rows])
        if name == "finish_raid":
            r = next(x for x in raids if x["id"] == rid)
            mine_first = r["status"] == "fighting"
            if mine_first:
                r.update(status="done", result=body["p_result"])
            return self._send(200, {"result": r["result"], "mine": mine_first})
        return self._send(404, {})

    def _team_rpc(self, name, body):
        if name in ("team_info", "team_messages_since"):
            state["old_polls"] = state.get("old_polls", 0) + 1
        uid = self._user()
        if uid is None:
            return self._send(401, {"message": "JWT invalid"})
        if name == "team_info":
            return self._send(200, self._team_of(uid, body.get("p_team")))
        if name == "my_teams":
            return self._send(200, [self._team_row(m["team_id"]) for m in members if m["user_id"] == uid])
        if name in ("create_team", "join_team"):
            if name == "create_team":
                tid = "t%d" % (len(teams) + 1)
                teams[tid] = {"code": "ABC%03d" % len(teams), "state": "", "version": 0}
            else:
                tid = next((k for k, t in teams.items() if t["code"] == body["p_code"]), None)
                if tid is None:
                    return self._send(400, {"message": "No team has that code."})
                if self._member(tid, uid):
                    return self._send(200, self._team_row(tid))
                if sum(1 for m in members if m["team_id"] == tid) >= 4:
                    return self._send(400, {"message": "That team is full (4 players)."})
            members.append({"team_id": tid, "user_id": uid, "name": body["p_name"], "zip": body["p_zip"]})
            return self._send(200, self._team_row(tid))
        if name == "send_team_message":
            mine = self._team_of(uid, body.get("p_team"))
            if not mine:
                return self._send(400, {"message": "You are not on that team."})
            body2 = (body.get("p_body") or "").strip()
            if not body2:
                return self._send(400, {"message": "Type a message first."})
            if sum(1 for m in chat if m["user_id"] == uid and time.time() - m["t"] < 10) >= 5:
                return self._send(400, {"message": "Slow down: wait a few seconds between messages."})
            me = next(m for m in members if m["user_id"] == uid and m["team_id"] == mine["id"])
            msg = {"id": len(chat) + 1, "team_id": mine["id"], "user_id": uid, "name": me["name"], "body": body2[:200],
                   "ping": body.get("p_ping") or "", "created_at": datetime.now(timezone.utc).isoformat(), "t": time.time()}
            chat.append(msg)
            return self._send(200, msg["id"])
        if name == "team_messages_since":
            mine = self._team_of(uid, body.get("p_team"))
            out = [{k: v for k, v in m.items() if k not in ("t", "team_id")} for m in chat
                   if mine and m["team_id"] == mine["id"] and m["id"] > body["p_after"]]
            return self._send(200, out[-100:])
        if name == "leave_team":
            members[:] = [m for m in members if not (m["user_id"] == uid and m["team_id"] == body.get("p_team"))]
            return self._send(200, None)
        if name == "save_team_state":
            time.sleep(slow.get("save_team_state", 0))
            mine = self._team_of(uid, body.get("p_team"))
            if not mine:
                return self._send(200, -1)
            t = teams[mine["id"]]
            if fail_next_save[0]:  # a teammate saves just before us
                fail_next_save[0] = False
                t["version"] += 1
            if t["version"] != body["p_version"]:
                return self._send(200, -1)
            t["state"] = body["p_state"]
            t["version"] += 1
            return self._send(200, t["version"])

    def _zcta(self):
        state["zcta_gets"] = state.get("zcta_gets", 0) + 1
        if slow.get("zcta_fails"):
            return self._send(500, {})
        if slow.get("zcta_garbage"):
            raw = b"<html>not it</html>"
        else:
            raw = (Path(__file__).resolve().parent.parent / "data" / "zcta" / self.path.split("/")[-1]).read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path.startswith("/zcta/"):
            return self._zcta()
        if self.path.startswith("/auth/v1/user"):
            return self._send(200, USER) if self._authed() else self._send(401, {"msg": "bad jwt"})
        if self.path.startswith("/rest/v1/saves"):
            return self._send(200, self._save_rows())
        if self.path == "/_state":
            return self._send(200, state)
        self._send(404, {})

    def do_POST(self):
        body = self._body()
        if self.path.startswith("/auth/v1/recover"):
            state["recover"].append({"email": body["email"], "path": self.path})
            return self._send(200, {})
        if self.path == "/_slow":
            slow.update(body)
            return self._send(200, {})
        if self.path.startswith("/auth/v1/token?grant_type=refresh_token"):
            state["refreshes"] += 1
            time.sleep(slow.get("refresh", 0))
            if slow.get("refresh_fails"):
                return self._send(400, {"error_description": "Invalid Refresh Token"})
            return self._send(200, {"access_token": state["token"], "refresh_token": "r3", "expires_in": 3600, "user": USER})
        if self.path.startswith("/auth/v1/token?grant_type=password"):
            if body["email"] == "b@b.co":
                if body["password"] != "bpass":
                    return self._send(400, {"error_description": "Invalid login credentials"})
                return self._send(200, {"access_token": "tok-b", "refresh_token": "rb", "expires_in": 3600, "user": USER_B})
            if body["password"] == state["password"]:
                return self._send(200, {"access_token": state["token"], "refresh_token": "r2", "expires_in": 3600, "user": USER})
            return self._send(400, {"error_description": "Invalid login credentials"})
        if self.path == "/_teammate_move":
            teams[body["team"]]["version"] += 1
            return self._send(200, {})
        if self.path == "/_teammate_says":
            chat.append({"id": len(chat) + 1, "team_id": body["team"], "user_id": "u2", "name": "Biscuit", "body": body["body"],
                         "ping": "", "created_at": "now", "t": time.time()})
            return self._send(200, {})
        if self.path == "/_remove_member":
            uid = self._user() or "u1"
            members[:] = [m for m in members if m["team_id"] != body["team"]]
            return self._send(200, {})
        if self.path == "/rest/v1/rpc/record_dungeon":
            if not self._authed():
                return self._send(401, {"message": "JWT invalid"})
            rec = state.setdefault("dungeons", {}).setdefault(body["p_region"], {})
            rec["u1"] = {"name": body["p_name"], "best": max(rec.get("u1", {}).get("best", 0), body["p_wave"])}
            return self._send(204, None)
        if self.path == "/rest/v1/rpc/dungeon_board":
            rec = state.get("dungeons", {}).get(body["p_region"], {})
            top = sorted(rec.values(), key=lambda r: -r["best"])[:10]
            return self._send(200, {"mine": rec.get("u1", {}).get("best", 0) if self._authed() else 0, "top": top})
        if self.path == "/rest/v1/rpc/team_pulse":
            return self._pulse(body or {})
        if self.path == "/rest/v1/battle_logs":
            if not self._authed():
                return self._send(401, {"message": "new row violates row-level security policy"})
            if slow.get("battle_status"):
                return self._send(slow["battle_status"], {"message": "no"})
            state.setdefault("battles", []).append(body)
            self.send_response(201)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/rest/v1/sync_events":
            if not self._authed():
                return self._send(401, {"message": "new row violates row-level security policy"})
            state.setdefault("sync_events", []).append(body)
            self.send_response(201)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/rest/v1/siege_hits":
            if not self._authed():
                return self._send(401, {"message": "new row violates row-level security policy"})
            state["hits"].append(dict(body, user="u1"))
            self.send_response(201)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/rest/v1/rpc/") and self.path.split("/")[-1] in ("team_info", "my_teams", "create_team", "join_team", "leave_team", "save_team_state", "send_team_message", "team_messages_since"):
            return self._team_rpc(self.path.split("/")[-1], body or {})
        if self.path.startswith("/rest/v1/rpc/") and self.path.split("/")[-1] in RAID_FNS:
            return self._raid_rpc(self.path.split("/")[-1], body or {})
        if self.path == "/_fail_next_save":
            fail_next_save[0] = True
            return self._send(200, {})
        if self.path == "/_teams":
            return self._send(200, {"teams": teams, "members": members})
        if self.path == "/rest/v1/rpc/siege_board":
            wk = [h for h in state["hits"] if h["week"] == body["p_week"]] + [h for h in state.get("others", []) if h["week"] == body["p_week"]]
            per = {}
            for h in wk:
                per.setdefault(h["user"], [h["name"], 0])[1] += h["points"]
            top = sorted(({"name": n, "points": p} for n, p in per.values()), key=lambda r: -r["points"])[:10]
            mine = sum(h["points"] for h in wk if h["user"] == "u1") if self._authed() else 0
            return self._send(200, {"total": sum(h["points"] for h in wk), "players": len(per), "mine": mine, "top": top})
        if self.path == "/_others":
            state["others"] = body
            return self._send(200, {})
        if self.path.startswith("/rest/v1/saves"):
            if slow.get("save_status"):  # uploads refused (reads still work)
                return self._send(slow["save_status"], {"message": "refused for the test"})
            uid = self._user()
            slot = body.get("slot", "save_cloud")
            if any(r["user"] == uid and r["slot"] == slot for r in state["saves"]):
                return self._send(409, {"code": "23505", "message": "duplicate key value violates unique constraint"})
            row = dict(body, user=uid, slot=slot, updated_at=stamp())
            state["saves"].append(row)
            return self._send(201, [row])
        if self.path == "/_bump":  # another device uploads game body["slot"] for u1
            row = next(r for r in state["saves"] if r["user"] == "u1" and r["slot"] == body["slot"])
            row.update(body, updated_at=stamp())
            return self._send(200, [row])
        self._send(404, {})

    def _save_rows(self):
        """This user's save rows, filtered by ?slot=eq.X (or not.like.X*) like PostgREST."""
        uid = self._user()
        q = parse_qs(urlparse(self.path).query)
        rule = q.get("slot", [""])[0]
        if rule.startswith("not.like."):
            prefix = rule.removeprefix("not.like.").removesuffix("*")
            return [r for r in state["saves"] if r["user"] == uid and not r["slot"].startswith(prefix)]
        slot = rule.removeprefix("eq.")
        rows = [r for r in state["saves"] if r["user"] == uid and (slot == "" or r["slot"] == slot)]
        has = q.get("profile", [""])[0]  # profile=like.*text*
        if has.startswith("like."):
            rows = [r for r in rows if has.removeprefix("like.").strip("*") in r.get("profile", "")]
        if q.get("order", [""])[0] == "updated_at.desc":
            rows = sorted(rows, key=lambda r: r["updated_at"], reverse=True)
        if q.get("limit"):
            rows = rows[:int(q["limit"][0])]
        return rows

    def do_DELETE(self):
        if self.path.startswith("/rest/v1/saves") and self._user():
            gone = self._save_rows()
            state["saves"][:] = [r for r in state["saves"] if r not in gone]
            return self._send(204, None)
        self._send(404, {})

    def do_PATCH(self):
        body = self._body()
        q = parse_qs(urlparse(self.path).query)
        want = q.get("updated_at", [""])[0].removeprefix("eq.")
        if self.path.startswith("/rest/v1/saves") and self._user():
            if slow.get("save_status"):
                return self._send(slow["save_status"], {"message": "refused for the test"})
            rows = [r for r in self._save_rows() if r["updated_at"] == want or "updated_at" not in q]  # (no version: a rename)
            if rows:
                rows[0].update(body, updated_at=stamp())
                return self._send(200, [rows[0]])
            return self._send(200, [])
        self._send(401, {})

    def do_PUT(self):
        body = self._body()
        if self.path == "/auth/v1/user" and self._authed():
            state["password"] = body["password"]
            return self._send(200, USER)
        self._send(401, {"msg": "nope"})


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
