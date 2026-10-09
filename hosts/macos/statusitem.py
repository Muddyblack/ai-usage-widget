"""The macOS menu bar item: a real NSStatusItem, through PyObjC.

Qt's QSystemTrayIcon gives an NSStatusItem an image and nothing else, and a
menu bar item that is only a picture is not what Mac users expect: the usage
belongs in the bar as text, in the system font, adapting to a light or dark
bar like every other item there. So on macOS the shared tray app
(hosts/desktop/app.py) uses this instead of Qt's tray icons:

  - the title is the pill's values ("23% · 61%") as attributed text, in the
    menu bar font; a value at 70%+ takes its warning colour, the rest stay the
    bar's own label colour;
  - the image is the active provider's logo, drawn by Qt from its SVG and
    marked as a template image, so macOS tints it for the bar like a system
    icon;
  - a click toggles the popup (placed under the item by TrayApp, which asks
    `geometry()` where that is), a right- or control-click opens the menu.

Everything runs on the main thread, in the same NSApplication Qt drives.
"""

import objc
from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSAttributedString,
    NSColor,
    NSData,
    NSEvent,
    NSEventMaskLeftMouseUp,
    NSEventMaskRightMouseUp,
    NSEventModifierFlagControl,
    NSEventTypeRightMouseUp,
    NSFont,
    NSFontAttributeName,
    NSForegroundColorAttributeName,
    NSImage,
    NSImageLeft,
    NSMakeSize,
    NSMutableAttributedString,
    NSScreen,
    NSStatusBar,
    NSVariableStatusItemLength,
)
from Foundation import NSObject
from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QPoint, QRect
from PySide6.QtGui import QColor, QIcon

ICON_POINTS = 16
WARNING_PCT = 70


def accessory_app():
    """No Dock tile and no app menu, also when run unbundled (the bundle's
    Info.plist says LSUIElement for the built app)."""
    NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)


def _ns_color(value):
    color = QColor(value)
    if not color.isValid():
        return None
    return NSColor.colorWithSRGBRed_green_blue_alpha_(color.redF(), color.greenF(), color.blueF(), 1.0)


def _template_image(url):
    """The logo at `url` (file://… SVG), as a template NSImage for the bar."""
    path = url[len("file://") :] if url.startswith("file://") else url
    if not path:
        return None
    pixmap = QIcon(path).pixmap(ICON_POINTS * 2, ICON_POINTS * 2)
    if pixmap.isNull():
        return None
    data = QByteArray()
    buffer = QBuffer(data)
    buffer.open(QIODevice.WriteOnly)
    pixmap.save(buffer, "PNG")
    buffer.close()
    image = NSImage.alloc().initWithData_(NSData.dataWithBytes_length_(bytes(data), len(data)))
    if image is None:
        return None
    image.setSize_(NSMakeSize(ICON_POINTS, ICON_POINTS))
    image.setTemplate_(True)
    return image


def slot_text(slot):
    text = slot.get("text") or ""
    return text if text else f"{round(slot.get('pct') or 0)}%"


class _Target(NSObject):
    """The button's action target; forwards to the Python callbacks."""

    def initWithOwner_(self, owner):
        self = objc.super(_Target, self).init()
        if self is None:
            return None
        self.owner = owner
        return self

    def clicked_(self, sender):
        event = NSApp.currentEvent()
        right = event is not None and (event.type() == NSEventTypeRightMouseUp or bool(event.modifierFlags() & NSEventModifierFlagControl))
        if right:
            self.owner.on_menu()
        else:
            self.owner.on_click()


class StatusItem:
    """One NSStatusItem showing the pill's values. `on_click()` toggles the
    popup, `on_menu()` opens the context menu; both are set by TrayApp."""

    def __init__(self, on_click, on_menu):
        self.on_click = on_click
        self.on_menu = on_menu
        self._item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
        self._target = _Target.alloc().initWithOwner_(self)
        button = self._item.button()
        button.setTarget_(self._target)
        button.setAction_(b"clicked:")
        button.sendActionOn_(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)
        button.setImagePosition_(NSImageLeft)
        self._icon_url = None
        self.update({})

    def update(self, state):
        """Show a tray state from ui/AppState.qml's publishTray():
        {style, icon, tooltip, slots: [{pct, color, text, tooltip}]}."""
        button = self._item.button()
        style = state.get("style") or "icons"
        slots = state.get("slots") or []
        icon = state.get("icon") or ""
        if icon != self._icon_url:
            self._icon_url = icon
            self._image = _template_image(icon)
        # "numbers" drops the logo; "ring" (one compact item) keeps only the
        # first value; "icons" shows the logo and every value.
        button.setImage_(None if style == "numbers" else self._image)
        shown = slots[:1] if style == "ring" else slots
        button.setAttributedTitle_(self._title(shown, leading_space=style != "numbers" and self._image is not None))
        button.setToolTip_(state.get("tooltip") or "AI Usage")

    def _title(self, slots, leading_space):
        font = NSFont.menuBarFontOfSize_(0)
        base = {NSFontAttributeName: font}
        title = NSMutableAttributedString.alloc().init()
        if not slots:
            text = "AI" if self._image is None else ""
            title.appendAttributedString_(NSAttributedString.alloc().initWithString_attributes_(text, base))
            return title
        if leading_space:
            title.appendAttributedString_(NSAttributedString.alloc().initWithString_attributes_(" ", base))
        for index, slot in enumerate(slots):
            if index:
                title.appendAttributedString_(NSAttributedString.alloc().initWithString_attributes_(" · ", base))
            attributes = dict(base)
            if (slot.get("pct") or 0) >= WARNING_PCT:
                color = _ns_color(slot.get("color"))
                if color is not None:
                    attributes[NSForegroundColorAttributeName] = color
            title.appendAttributedString_(NSAttributedString.alloc().initWithString_attributes_(slot_text(slot), attributes))
        return title

    def geometry(self):
        """The item's rectangle in Qt's global coordinates (top-left origin,
        points), for placing the popup under it."""
        window = self._item.button().window()
        if window is None:
            return QRect()
        frame = window.frame()
        primary_height = NSScreen.screens()[0].frame().size.height
        top = primary_height - (frame.origin.y + frame.size.height)
        return QRect(int(frame.origin.x), int(top), int(frame.size.width), int(frame.size.height))

    def menu_position(self):
        rect = self.geometry()
        if rect.isValid():
            return QPoint(rect.left(), rect.bottom() + 4)
        location = NSEvent.mouseLocation()
        return QPoint(int(location.x), int(NSScreen.screens()[0].frame().size.height - location.y))

    @staticmethod
    def activate():
        """Bring the app forward, so the popup gets focus — and loses it, and
        closes, on a click anywhere else."""
        NSApp.activateIgnoringOtherApps_(True)

    def remove(self):
        NSStatusBar.systemStatusBar().removeStatusItem_(self._item)
