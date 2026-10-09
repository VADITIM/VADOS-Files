#include "fileManagerService.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QProcess>
#include <QProcessEnvironment>
#include <QUrl>

FileManagerService::FileManagerService(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
}

int FileManagerService::run(int argumentCount, char *argumentValues[])
{
    QCoreApplication application(argumentCount, argumentValues);
    QObject root;
    new FileManagerService(&root);
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/org/freedesktop/FileManager1"), &root) || !bus.registerService(QStringLiteral("org.freedesktop.FileManager1")))
        return 1;
    return application.exec();
}

void FileManagerService::ShowFolders(const QStringList &uris, const QString &startupId)
{
    openWindows(uris, startupId);
}

// The window opens at the item's folder; the launch argument already resolves a file to its parent.
void FileManagerService::ShowItems(const QStringList &uris, const QString &startupId)
{
    openWindows(uris, startupId);
}

void FileManagerService::ShowItemProperties(const QStringList &uris, const QString &startupId)
{
    openWindows(uris, startupId);
}

void FileManagerService::openWindows(const QStringList &uris, const QString &startupId)
{
    for (const QString &uri : uris) {
        QProcess process;
        process.setProgram(QCoreApplication::applicationFilePath());
        process.setArguments({QUrl(uri).isLocalFile() ? QUrl(uri).toLocalFile() : uri});
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        if (!startupId.isEmpty())
            environment.insert(QStringLiteral("XDG_ACTIVATION_TOKEN"), startupId);
        process.setProcessEnvironment(environment);
        process.startDetached();
    }
}
