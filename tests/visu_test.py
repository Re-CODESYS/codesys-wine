# encoding:utf-8
# CODESYS script: open a project, add a Visualization object, check that a
# visualization profile is available, build, and append the outcome to a
# result file. Started by run-visu-test.sh. Paths come from environment
# variables set by the runner (Windows paths).
import os
import traceback

import System
from System.Reflection import BindingFlags

OUT = os.environ["CWT_RESULT"]
PROJECT = os.environ["CWT_PROJECT"]
ALL = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance


def log(msg):
    with open(OUT, "a") as f:
        f.write(msg + "\n")


def profile_manager():
    # Internal API, read through reflection: the profile list is what fills the
    # Visualization Toolbox, and it is empty when the element repository is broken.
    name = "_3S.CoDeSys.VisualElemRepository.Profiles.VisualProfileManager"
    for a in System.AppDomain.CurrentDomain.GetAssemblies():
        t = a.GetType(name)
        if t is not None:
            return t, t.GetProperty("Singleton", ALL).GetValue(None, None)
    return None, None


def messages():
    for cat in system.get_message_categories(True):
        for m in system.get_message_objects(cat):
            yield str(m)


log("START")
try:
    proj = projects.open(PROJECT)
    app = proj.active_application
    if not proj.find("VisuTest", True):
        app.create_visualobject("VisuTest")
    t, mgr = profile_manager()
    if mgr is None:
        log("SCRIPT_ERROR VisualProfileManager not found (Visualization package missing?)")
    else:
        available = [p.Name for p in t.GetProperty("AvailableProfiles", ALL).GetValue(mgr, None)]
        active = t.GetProperty("ActiveProfile", ALL).GetValue(mgr, None)
        log("profiles: %s" % available)
        app.build()
        for m in messages():
            if "repository for visual elements" in m or "Compile complete" in m:
                log("message: %s" % m)
        if available and active is not None:
            log("VISU_OK profile=%s" % active.Name)
        else:
            log("VISU_FAIL no visualization profile")
    proj.close()
except Exception as e:
    log("SCRIPT_ERROR %s" % e)
    log(traceback.format_exc())
log("END")
