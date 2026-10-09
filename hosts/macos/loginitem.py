"""Start at login on macOS 13+, through SMAppService (ServiceManagement).

The app registers itself as a login item the way Apple's own API intends: it
shows by name under System Settings → General → Login Items, the user can
switch it off there, and macOS does not post the "background item added"
notice a hand-written LaunchAgent plist gets.

SMAppService only knows an app bundle, so this works only in the built
AI Usage.app; app.py falls back to the LaunchAgent when run from a checkout.
"""

from ServiceManagement import (
    SMAppService,
    SMAppServiceStatusEnabled,
    SMAppServiceStatusRequiresApproval,
)


def enabled():
    """On, or waiting for the user's approval in System Settings (which is
    still the user's "on": macOS asks, the app does not ask again)."""
    status = SMAppService.mainAppService().status()
    return status in (SMAppServiceStatusEnabled, SMAppServiceStatusRequiresApproval)


def set_enabled(on):
    service = SMAppService.mainAppService()
    if on:
        ok, error = service.registerAndReturnError_(None)
        if ok and service.status() == SMAppServiceStatusRequiresApproval:
            # The user turned login items off for this app before: macOS wants
            # them to say yes again, in System Settings.
            SMAppService.openSystemSettingsLoginItems()
    elif not enabled():
        # Unregistering what was never registered is an error, not a no-op.
        return
    else:
        ok, error = service.unregisterAndReturnError_(None)
    if not ok and error is not None:
        raise OSError(str(error.localizedDescription()))
