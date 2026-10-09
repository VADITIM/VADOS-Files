#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQuickStyle>
#include <QUrl>

#include "fileManagerService.h"
#include "picker.h"
#include "portalService.h"
#include "imageProviders.h"
#include "system.h"

namespace {

// Fonts are registered once, at the root, never by a component (VAS typography). Bundled files come first; the user font folder is the fallback for faces that cannot be redistributed.
void registerFonts()
{
    QDirIterator bundled(QStringLiteral(":/assets/fonts"), {QStringLiteral("*.ttf"), QStringLiteral("*.otf")}, QDir::Files);
    while (bundled.hasNext())
        QFontDatabase::addApplicationFont(bundled.next());
}

QString pathFromArguments(const QStringList &arguments)
{
    for (int index = 1; index < arguments.size(); ++index) {
        const QString argument = arguments.at(index);
        if (argument.startsWith(QLatin1Char('-')))
            continue;
        const QUrl url(argument);
        const QString path = url.isLocalFile() ? url.toLocalFile() : argument;
        const QFileInfo info(path);
        if (info.isDir())
            return info.absoluteFilePath();
        if (info.exists())
            return info.absolutePath();
    }
    return QString();
}

} // namespace

int main(int argumentCount, char *argumentValues[])
{
    // Started by D-Bus activation for "show in folder"; opens windows on request and shows none itself.
    for (int index = 1; index < argumentCount; ++index)
        if (qstrcmp(argumentValues[index], "--file-manager-service") == 0)
            return FileManagerService::run(argumentCount, argumentValues);
    // Started by D-Bus activation as the file chooser behind xdg-desktop-portal; each request runs this binary again with --pick.
    for (int index = 1; index < argumentCount; ++index)
        if (qstrcmp(argumentValues[index], "--portal-service") == 0)
            return PortalService::run(argumentCount, argumentValues);
    QString pickerFolder;
    for (int index = 1; index + 1 < argumentCount; ++index)
        if (qstrcmp(argumentValues[index], "--pick") == 0)
            pickerFolder = Picker::configure(argumentValues[index + 1]);

    // Hyprland draws no decorations, and Qt's fallback client-side frame is a light bar that is not part of this design.
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    // Qt's text-input-v3 client logs a harmless line on every focus change between fields under Hyprland. QT_LOGGING_RULES still overrides this.
    QLoggingCategory::setFilterRules(QStringLiteral("qt.qpa.wayland.textinput=false"));
    QGuiApplication application(argumentCount, argumentValues);
    application.setApplicationName(QStringLiteral("VAD/OS Files"));
    application.setOrganizationName(QStringLiteral("vados"));
    // The Wayland app_id, so Hyprland window rules can target `class:^(vados-files)$`.
    application.setDesktopFileName(QStringLiteral("vados-files"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    registerFonts();
    System::setInitialPath(pickerFolder.isEmpty() ? pathFromArguments(application.arguments()) : pickerFolder);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("thumbnail"), new ThumbnailProvider);
    engine.addImageProvider(QStringLiteral("glyph"), new GlyphProvider);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &application, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Vados", "Main");

    // Development only: a scripted run that drives the window and saves frames, for checking motion and layout without anyone's hands on the pointer.
    const QString rehearsal = qEnvironmentVariable("VADOS_REHEARSAL");
    if (!rehearsal.isEmpty() && !engine.rootObjects().isEmpty()) {
        QQmlComponent component(&engine, QUrl::fromLocalFile(rehearsal));
        QObject *script = component.createWithInitialProperties({{QStringLiteral("window"), QVariant::fromValue(engine.rootObjects().first())}});
        if (!script)
            qWarning().noquote() << component.errorString();
    }
    return application.exec();
}
