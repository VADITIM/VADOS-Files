#pragma once

#include <QDBusAbstractAdaptor>
#include <QStringList>

// org.freedesktop.FileManager1: what browsers, Electron apps and terminals call for "show in folder". Each call opens a window of this app at the folder.
class FileManagerService : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.FileManager1")

public:
    explicit FileManagerService(QObject *parent);

    // Runs headless, owning the bus name until the session ends; returns the exit code.
    static int run(int argumentCount, char *argumentValues[]);

public slots:
    void ShowFolders(const QStringList &uris, const QString &startupId);
    void ShowItems(const QStringList &uris, const QString &startupId);
    void ShowItemProperties(const QStringList &uris, const QString &startupId);

private:
    void openWindows(const QStringList &uris, const QString &startupId);
};
