# VM test of the NixOS module (ADR 0090): the service starts, serves the app, applies the migrations, reads its
# secrets from the environment file, keeps its data across a restart, and the admin CLI writes as the service user.
{ module }:
{
  name = "atlas-nixos-module";

  nodes.machine = { pkgs, ... }: {
    imports = [ module ];
    services.atlas = {
      enable = true;
      publicUrl = "https://atlas.example.org";
      # Only a test file in the store; a real host keeps this outside the store.
      environmentFile = pkgs.writeText "atlas.env" ''
        STRAVA_CLIENT_ID=12345
        STRAVA_CLIENT_SECRET=test-secret
        STRAVA_VERIFY_TOKEN=test-verify
      '';
    };
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    import json

    def api(method, path, body=None, token=None):
        args = f"-s -X {method} http://127.0.0.1:8090{path}"
        if token:
            args += f" -H 'Authorization: {token}'"
        if body is not None:
            args += f" -H 'Content-Type: application/json' -d '{json.dumps(body)}'"
        return json.loads(machine.succeed(f"curl {args}"))

    machine.wait_for_unit("atlas.service")
    machine.wait_for_open_port(8090)

    with subtest("serves the app and its service worker"):
        machine.succeed("curl -sf http://127.0.0.1:8090/api/health")
        machine.succeed("curl -sf http://127.0.0.1:8090/ | grep -q '<html'")
        machine.succeed("curl -sf http://127.0.0.1:8090/sw.js | grep -q 'atlas-shell-'")
        machine.succeed("curl -sf http://127.0.0.1:8090/settings | grep -q '<html'")

    with subtest("listens on the local address only"):
        machine.fail("curl -sf --max-time 5 http://$(hostname -I | awk '{print $1}'):8090/api/health")

    with subtest("the admin CLI runs as the service user"):
        machine.succeed("atlas-pocketbase superuser upsert admin@example.org admin-password-123")
        machine.succeed("test \"$(stat -c %U /var/lib/atlas/pb_data/data.db)\" = atlas")
        machine.succeed("test \"$(find /var/lib/atlas -not -user atlas | wc -l)\" = 0")

    with subtest("the migrations ran and the hooks see the environment file"):
        admin = api("POST", "/api/collections/_superusers/auth-with-password",
                    {"identity": "admin@example.org", "password": "admin-password-123"})["token"]
        api("POST", "/api/collections/users/records",
            {"email": "alice@example.org", "password": "alice-password-1", "passwordConfirm": "alice-password-1", "name": "alice"},
            token=admin)
        alice = api("POST", "/api/collections/users/auth-with-password",
                    {"identity": "alice@example.org", "password": "alice-password-1"})["token"]
        assert api("GET", "/api/collections/plans/records", token=alice)["items"] == []
        status = api("GET", "/api/atlas/strava/status", token=alice)
        assert status == {"configured": True, "connected": False}, status

    with subtest("the data survives a restart"):
        machine.systemctl("restart atlas.service")
        machine.wait_for_open_port(8090)
        api("POST", "/api/collections/users/auth-with-password",
            {"identity": "alice@example.org", "password": "alice-password-1"})["token"]
  '';
}
