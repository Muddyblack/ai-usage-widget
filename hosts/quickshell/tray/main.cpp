#include <QAction>
#include <QApplication>
#include <QColor>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLinearGradient>
#include <QMenu>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QPixmap>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSystemTrayIcon>
#include <QTimer>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setApplicationName("AI Usage Widget");
    app.setQuitOnLastWindowClosed(false);

    if (argc != 4)
        return 2;

    const QString qsPath = QString::fromLocal8Bit(argv[1]);
    const QString configPath = QString::fromLocal8Bit(argv[2]);
    const QString backendPath = QString::fromLocal8Bit(argv[3]);

    auto call = [&](const QString &method) {
        QProcess::startDetached(qsPath, {"ipc", "-p", configPath, "call", "panel", method});
    };

    QPixmap iconPixmap(64, 64);
    iconPixmap.fill(Qt::transparent);
    QPainter painter(&iconPixmap);
    painter.setRenderHint(QPainter::Antialiasing);
    QLinearGradient gradient(8, 8, 56, 56);
    gradient.setColorAt(0.0, QColor("#ff007f"));
    gradient.setColorAt(0.35, QColor("#a855f7"));
    gradient.setColorAt(0.70, QColor("#00f0ff"));
    gradient.setColorAt(1.0, QColor("#00ff7f"));
    QPen pen(QBrush(gradient), 5, Qt::SolidLine, Qt::RoundCap);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);
    painter.drawArc(QRectF(9, 16, 46, 38), 195 * 16, 150 * 16);
    painter.setOpacity(0.55);
    painter.drawArc(QRectF(17, 22, 30, 24), 195 * 16, 150 * 16);
    painter.setOpacity(1.0);
    painter.setPen(Qt::NoPen);
    painter.setBrush(QBrush(gradient));
    QPainterPath star;
    star.moveTo(32, 5);
    star.cubicTo(32, 17, 36, 21, 48, 21);
    star.cubicTo(36, 21, 32, 25, 32, 37);
    star.cubicTo(32, 25, 28, 21, 16, 21);
    star.cubicTo(28, 21, 32, 17, 32, 5);
    painter.drawPath(star);
    painter.end();

    QSystemTrayIcon tray{QIcon(iconPixmap)};
    tray.setToolTip("AI Usage");

    // The popup's settings page writes an optional interpreter override into the
    // shared JSON config (same path shell.qml derives). This helper runs the
    // backend on its own, so without this it would keep using PATH's Python
    // while the popup used the configured one. Re-read on every refresh so a
    // change takes effect without restarting the tray.
    const auto configuredPython = [] {
        QString base = qEnvironmentVariable("XDG_CONFIG_HOME");
        if (base.isEmpty())
            base = QDir::homePath() + "/.config";
        QFile file(base + "/ai-usage-widget/hyprland-settings.json");
        if (!file.open(QIODevice::ReadOnly))
            return QString();
        return QJsonDocument::fromJson(file.readAll()).object().value("pythonPath").toString().trimmed();
    };

    QProcess backend;
    auto updateTooltip = [&] {
        if (backend.state() != QProcess::NotRunning)
            return;
        auto environment = QProcessEnvironment::systemEnvironment();
        const QString python = configuredPython();
        if (!python.isEmpty())
            environment.insert("PYTHON3", python);
        backend.setProcessEnvironment(environment);
        backend.start(backendPath, {"--all"});
    };
    QObject::connect(&backend, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), [&](int, QProcess::ExitStatus) {
        const auto document = QJsonDocument::fromJson(backend.readAllStandardOutput());
        const auto providers = document.object().value("providers").toArray();
        QStringList lines{"AI Usage"};
        for (const auto &value : providers) {
            const auto provider = value.toObject();
            const QString label = provider.value("label").toString();
            const QString summary = provider.value("summary").toObject().value("text").toString();
            if (!label.isEmpty() && !summary.isEmpty())
                lines.append(label + ": " + summary);
        }
        tray.setToolTip(lines.join('\n'));
    });

    QTimer tooltipTimer;
    tooltipTimer.setInterval(300000);
    QObject::connect(&tooltipTimer, &QTimer::timeout, updateTooltip);
    tooltipTimer.start();
    QTimer::singleShot(0, updateTooltip);

    QMenu menu;
    auto *openAction = menu.addAction("Open AI Usage");
    auto *refreshAction = menu.addAction("Refresh");
    menu.addSeparator();
    auto *quitAction = menu.addAction("Quit AI Usage");
    // Caelestia presents a StatusNotifier context menu while its tray item is
    // hovered. Treat that menu lifetime as the portable helper's hover signal.
    QObject::connect(&menu, &QMenu::aboutToShow, [&] { call("trayEnter"); });
    QObject::connect(&menu, &QMenu::aboutToHide, [&] { call("trayLeave"); });
    QObject::connect(openAction, &QAction::triggered, [&] { call("toggle"); });
    QObject::connect(refreshAction, &QAction::triggered, [&] {
        call("refresh");
        updateTooltip();
    });
    QObject::connect(quitAction, &QAction::triggered, [&] {
        call("quit");
        QTimer::singleShot(300, &app, &QApplication::quit);
    });
    tray.setContextMenu(&menu);
    QObject::connect(&tray, &QSystemTrayIcon::activated, [&](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
            call("toggle");
    });

    tray.show();
    return app.exec();
}
