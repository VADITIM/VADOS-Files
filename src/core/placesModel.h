#pragma once

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// The sidebar's rows: the user's pins (ordered, named, iconed, all editable) and then the drives, which come and go on their own.
// Separately it keeps the rooms (HOME, the XDG folders, SYSTEM, TRASH, mounted drives), which give a path its accent whether or not anything is pinned.
class PlacesModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int pinCount READ pinCount NOTIFY pinsChanged)
    Q_PROPERTY(QStringList iconChoices READ iconChoices CONSTANT)

public:
    enum Role { NameRole = Qt::UserRole + 1, PathRole, KeyRole, SectionRole, DeviceRole, IsMountedRole, CanEjectRole, UsageRole, DetailRole, IconRole, AccentKeyRole, GroupRole };

    struct Place {
        QString name;
        QString path;
        // What Theme maps to an accent and a glyph; colours live in the design layer, never here.
        QString key;
        QString section;
        QString icon;
        // A colour the user chose for a pin: a key of Theme.placeAccents, empty to follow the room.
        QString tint;
        QString device;
        QString detail;
        double usage = -1;
        bool isMounted = true;
        bool canEject = false;
    };

    explicit PlacesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // The place a path belongs to: the deepest registered root that contains it.
    Q_INVOKABLE QVariantMap placeFor(const QString &path) const;
    Q_INVOKABLE void mount(const QString &device);
    Q_INVOKABLE void unmount(const QString &device);
    Q_INVOKABLE void refreshDrives();

    int pinCount() const { return int(m_pins.size()); }
    QStringList iconChoices() const;
    Q_INVOKABLE bool isPinned(const QString &path) const;
    // Pins the folder at `row` (appends when -1), named after the folder, with the icon its room would use.
    Q_INVOKABLE void pin(const QString &path, int row = -1);
    Q_INVOKABLE void unpin(const QString &path);
    // Moves live, for a drag in progress; the order is saved as it changes.
    Q_INVOKABLE void movePin(int from, int to);
    Q_INVOKABLE void renamePin(int row, const QString &name);
    Q_INVOKABLE void setPinIcon(int row, const QString &icon);
    Q_INVOKABLE void setPinTint(int row, const QString &tint);
    Q_INVOKABLE QString tintAt(int row) const;
    // The colour the user gave the deepest pin containing this path, empty if none.
    Q_INVOKABLE QString tintFor(const QString &path) const;
    // The pin to light for a folder: the one pinned at exactly that path, else the room root it sits in, if that is pinned.
    Q_INVOKABLE QString litPathFor(const QString &path) const;

signals:
    void mounted(const QString &device, const QString &path);
    void failed(const QString &message);
    void pinsChanged();

private:
    void rebuild();
    void buildRooms();
    void loadPins();
    void savePins() const;
    Place roomFor(const QString &path) const;
    QString defaultIconFor(const QString &key) const;
    // Pins sit in three runs split by dividers: HOME, DOWNLOADS and SYSTEM; everything else; the trash.
    int groupOf(const Place &place) const;

    QList<Place> m_rooms;
    QList<Place> m_pins;
    QList<Place> m_places;
    QList<Place> m_drives;
    QFileSystemWatcher m_watcher;
    QTimer m_driveDebounce;
};
