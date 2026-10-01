# encoding:utf-8
# CODESYS script: open a project, switch its devices to simulation, log in,
# and append the outcome to a result file. Started by run-login-test.sh.
# Paths come from environment variables set by the runner (Windows paths).
import os
import traceback

OUT = os.environ["CWT_RESULT"]
PROJECT = os.environ["CWT_PROJECT"]


def log(msg):
    with open(OUT, "a") as f:
        f.write(msg + "\n")


log("START")
try:
    proj = projects.open(PROJECT)
    devs = [o for o in proj.get_children(True) if hasattr(o, "set_simulation_mode")]
    log("devices: %d" % len(devs))
    for d in devs:
        d.set_simulation_mode(True)
    app = proj.active_application
    log("app: %s" % app.get_name())
    onl = online.create_online_application(app)
    try:
        onl.login(OnlineChangeOption.Try, True)
        log("LOGIN_OK state=%s" % onl.application_state)
        onl.logout()
    except Exception as e:
        log("LOGIN_FAIL %s" % e)
        log(traceback.format_exc())
    proj.close()
except Exception as e:
    log("SCRIPT_ERROR %s" % e)
    log(traceback.format_exc())
log("END")
