#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QJsonObject>
#include <QVariantMap>

class QProcess;

// org.freedesktop.impl.portal.FileChooser: the backend xdg-desktop-portal asks when any app wants a file picked or saved. Each request opens a window of this app in picker mode and answers when it closes.
class PortalService : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")
    Q_CLASSINFO("D-Bus Introspection",
        "<interface name=\"org.freedesktop.impl.portal.FileChooser\">"
        "<method name=\"OpenFile\"><arg type=\"o\" name=\"handle\" direction=\"in\"/><arg type=\"s\" name=\"app_id\" direction=\"in\"/><arg type=\"s\" name=\"parent_window\" direction=\"in\"/><arg type=\"s\" name=\"title\" direction=\"in\"/><arg type=\"a{sv}\" name=\"options\" direction=\"in\"/><arg type=\"u\" name=\"response\" direction=\"out\"/><arg type=\"a{sv}\" name=\"results\" direction=\"out\"/></method>"
        "<method name=\"SaveFile\"><arg type=\"o\" name=\"handle\" direction=\"in\"/><arg type=\"s\" name=\"app_id\" direction=\"in\"/><arg type=\"s\" name=\"parent_window\" direction=\"in\"/><arg type=\"s\" name=\"title\" direction=\"in\"/><arg type=\"a{sv}\" name=\"options\" direction=\"in\"/><arg type=\"u\" name=\"response\" direction=\"out\"/><arg type=\"a{sv}\" name=\"results\" direction=\"out\"/></method>"
        "<method name=\"SaveFiles\"><arg type=\"o\" name=\"handle\" direction=\"in\"/><arg type=\"s\" name=\"app_id\" direction=\"in\"/><arg type=\"s\" name=\"parent_window\" direction=\"in\"/><arg type=\"s\" name=\"title\" direction=\"in\"/><arg type=\"a{sv}\" name=\"options\" direction=\"in\"/><arg type=\"u\" name=\"response\" direction=\"out\"/><arg type=\"a{sv}\" name=\"results\" direction=\"out\"/></method>"
        "</interface>")

public:
    explicit PortalService(QObject *parent);

    // Runs headless, owning the bus name until the session ends; returns the exit code.
    static int run(int argumentCount, char *argumentValues[]);

public slots:
    void OpenFile(const QDBusObjectPath &handle, const QString &appId, const QString &parentWindow, const QString &title, const QVariantMap &options, const QDBusMessage &message);
    void SaveFile(const QDBusObjectPath &handle, const QString &appId, const QString &parentWindow, const QString &title, const QVariantMap &options, const QDBusMessage &message);
    void SaveFiles(const QDBusObjectPath &handle, const QString &appId, const QString &parentWindow, const QString &title, const QVariantMap &options, const QDBusMessage &message);

private:
    // `names` is set only for SaveFiles: the picked folder is joined with each name.
    void ask(const QDBusObjectPath &handle, const QJsonObject &request, const QVariantMap &options, const QStringList &names, const QDBusMessage &message);
};

// org.freedesktop.impl.portal.Request on the handle path: the asking app gave up, so the picker window goes.
class PortalRequest : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")

public:
    PortalRequest(QObject *parent, QProcess *process);

public slots:
    void Close();

private:
    QProcess *m_process;
};
