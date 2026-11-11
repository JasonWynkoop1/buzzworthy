"""Small App Store Connect helper for the TestFlight workflow.

Usage: python3 asc.py prepare BUNDLE_ID APP_NAME
Needs env ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file).
Registers the bundle ID if needed, finds the team ID, checks the app exists
in App Store Connect, and sets up an internal TestFlight group that gets
every build and includes everyone on the account. Writes key=value lines to
$GITHUB_OUTPUT.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None, params=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")}


def output(**kv):
    path = os.environ.get("GITHUB_OUTPUT")
    lines = "".join(f"{k}={v}\n" for k, v in kv.items())
    print(lines, end="")
    if path:
        with open(path, "a") as f:
            f.write(lines)


def prepare(bundle_id, app_name):
    status, res = call("GET", "/v1/bundleIds", params={"filter[identifier]": bundle_id, "limit": 200})
    if status != 200:
        sys.exit(f"Could not read bundle IDs ({status}). Check the API key secrets. {res}")
    match = [b for b in res.get("data", []) if b["attributes"]["identifier"] == bundle_id]
    if match:
        bundle = match[0]
    else:
        status, res = call("POST", "/v1/bundleIds", {
            "data": {"type": "bundleIds", "attributes": {"identifier": bundle_id, "name": app_name, "platform": "IOS"}}
        })
        if status not in (200, 201):
            sys.exit(f"Could not register bundle ID {bundle_id} ({status}): {res}")
        bundle = res["data"]
        print(f"Registered bundle ID {bundle_id}")
    team = bundle["attributes"].get("seedId", "")

    status, res = call("GET", "/v1/apps", params={"filter[bundleId]": bundle_id})
    apps = [a for a in res.get("data", []) if a["attributes"].get("bundleId") == bundle_id] if status == 200 else []
    if not apps:
        output(team_id=team, app_exists="false")
        print(f"::warning::No app with bundle ID {bundle_id} in App Store Connect yet. "
              f"Create it (Apps, +, New App, tvOS, bundle ID {bundle_id}) and run this workflow again.")
        return
    app_id = apps[0]["id"]

    try:
        setup_testers(app_id)
    except Exception as e:  # never block the upload over tester setup
        print(f"::warning::Could not set up the TestFlight group automatically: {e}")
    output(team_id=team, app_exists="true", app_id=app_id)


def setup_testers(app_id):
    status, res = call("GET", f"/v1/apps/{app_id}/betaGroups", params={"limit": 200})
    groups = [g for g in res.get("data", []) if g["attributes"].get("isInternalGroup")] if status == 200 else []
    group = next((g for g in groups if g["attributes"]["name"] == "Family"), None)
    if not group:
        status, res = call("POST", "/v1/betaGroups", {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": "Family", "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if status not in (200, 201):
            raise RuntimeError(f"create group {status}: {res}")
        group = res["data"]
        print("Created internal TestFlight group 'Family'")
    gid = group["id"]

    status, res = call("GET", "/v1/users", params={"limit": 200})
    for u in res.get("data", []) if status == 200 else []:
        a = u["attributes"]
        email = a.get("username") or a.get("email")
        if not email:
            continue
        st, r = call("POST", "/v1/betaTesters", {
            "data": {
                "type": "betaTesters",
                "attributes": {"email": email, "firstName": a.get("firstName", ""), "lastName": a.get("lastName", "")},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}},
            }
        })
        if st in (200, 201):
            print("Added a tester to the Family group")
        elif st == 409:
            st2, r2 = call("GET", "/v1/betaTesters", params={"filter[email]": email})
            for t in r2.get("data", []):
                call("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters",
                     {"data": [{"type": "betaTesters", "id": t["id"]}]})
        else:
            print(f"::warning::Could not add a tester ({st})")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "prepare":
        prepare(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
