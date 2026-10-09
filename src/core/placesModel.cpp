#include <algorithm>
#include "placesModel.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>

#include <functional>

namespace {

QString bookmarksFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/gtk-3.0/bookmarks");
}

const QString PINS_KEY = QStringLiteral("pins");

// Mount points that are the system itself rather than something plugged in; they are reached through SYSTEM, not listed as drives.
bool isSystemMount(const QString &mountPoint)
{
    static const QStringList system = {QStringLiteral("/"), QStringLiteral("/boot"), QStringLiteral("/efi"), QStringLiteral("/boot/efi"), QStringLiteral("/home"), QStringLiteral("[SWAP]")};
    return system.contains(mountPoint);
}

} // namespace

// #region ── lifecycle ───────────────────────────────────────────────────────────────────────

PlacesModel::PlacesModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_driveDebounce.setSingleShot(true);
    m_driveDebounce.setInterval(400);
    connect(&m_driveDebounce, &QTimer::timeout, this, &PlacesModel::refreshDrives);
    // Device nodes appear and vanish under /dev/disk/by-uuid as drives are plugged, and mount points under /run/media; watching both catches a plug and a mount without polling.
    for (const QString &watched : {QStringLiteral("/dev/disk/by-uuid"), QStringLiteral("/run/media/") + qEnvironmentVariable("USER")})
        if (QFileInfo(watched).isDir())
            m_watcher.addPath(watched);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_driveDebounce.start(); });
    buildRooms();
    loadPins();
    rebuild();
    refreshDrives();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── model ───────────────────────────────────────────────────────────────────────────

int PlacesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_places.size());
}

QVariant PlacesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_places.size())
        return {};
    const Place &place = m_places.at(index.row());
    switch (role) {
    case NameRole: return place.name;
    case PathRole: return place.path;
    case KeyRole: return place.key;
    case SectionRole: return place.section;
    case DeviceRole: return place.device;
    case IsMountedRole: return place.isMounted;
    case CanEjectRole: return place.canEject;
    case UsageRole: return place.usage;
    case DetailRole: return place.detail;
    case IconRole: return place.icon;
    // A pin is coloured by the room its folder sits in, so a pinned project inside HOME is green like HOME.
    case AccentKeyRole: return !place.tint.isEmpty() ? place.tint : place.section == QLatin1String("drives") ? place.key : roomFor(place.path).key;
    case GroupRole: return groupOf(place);
    }
    return {};
}

QHash<int, QByteArray> PlacesModel::roleNames() const
{
    return {{NameRole, "name"}, {PathRole, "path"}, {KeyRole, "key"}, {SectionRole, "section"}, {DeviceRole, "device"},
            {IsMountedRole, "isMounted"}, {CanEjectRole, "canEject"}, {UsageRole, "usage"}, {DetailRole, "detail"},
            {IconRole, "icon"}, {AccentKeyRole, "accentKey"}, {GroupRole, "group"}};
}

void PlacesModel::buildRooms()
{
    QList<Place> rooms;
    const QString home = QDir::homePath();
    rooms.append({QStringLiteral("Home"), home, QStringLiteral("home"), QStringLiteral("rooms")});
    const QList<std::pair<QStandardPaths::StandardLocation, QString>> standard = {
        {QStandardPaths::DesktopLocation, QStringLiteral("desktop")},
        {QStandardPaths::DocumentsLocation, QStringLiteral("documents")},
        {QStandardPaths::DownloadLocation, QStringLiteral("downloads")},
        {QStandardPaths::PicturesLocation, QStringLiteral("pictures")},
        {QStandardPaths::MusicLocation, QStringLiteral("music")},
        {QStandardPaths::MoviesLocation, QStringLiteral("videos")},
    };
    QStringList seen = {home};
    for (const auto &[location, key] : standard) {
        const QString path = QStandardPaths::writableLocation(location);
        // user-dirs.dirs routinely points several of these at $HOME; a second HOME is noise, and a missing folder is a dead room.
        if (path.isEmpty() || seen.contains(path) || !QFileInfo(path).isDir())
            continue;
        seen.append(path);
        rooms.append({QFileInfo(path).fileName(), path, key, QStringLiteral("rooms")});
    }
    rooms.append({QStringLiteral("System"), QStringLiteral("/"), QStringLiteral("system"), QStringLiteral("rooms")});
    rooms.append({QStringLiteral("Trash"), QStringLiteral("trash:///"), QStringLiteral("trash"), QStringLiteral("rooms")});
    m_rooms = rooms;
}

void PlacesModel::rebuild()
{
    beginResetModel();
    m_places = m_pins + m_drives;
    endResetModel();
    emit pinsChanged();
}

PlacesModel::Place PlacesModel::roomFor(const QString &path) const
{
    const Place *best = nullptr;
    for (const QList<Place> *list : {&m_rooms, &m_drives}) {
        for (const Place &place : *list) {
            if (!place.isMounted || place.path.isEmpty())
                continue;
            const bool isInside = path == place.path || (place.path == QLatin1String("/") ? path.startsWith(QLatin1Char('/')) : path.startsWith(place.path + QLatin1Char('/')));
            if (isInside && (!best || place.path.size() > best->path.size()))
                best = &place;
        }
    }
    if (!best)
        return {QStringLiteral("System"), QStringLiteral("/"), QStringLiteral("system"), QStringLiteral("rooms")};
    return *best;
}

QVariantMap PlacesModel::placeFor(const QString &path) const
{
    const Place room = roomFor(path);
    return {{QStringLiteral("key"), room.key}, {QStringLiteral("name"), room.name}, {QStringLiteral("path"), room.path}};
}

QString PlacesModel::litPathFor(const QString &path) const
{
    for (const Place &pin : m_pins)
        if (pin.path == path)
            return pin.path;
    const Place room = roomFor(path);
    for (const Place &pin : m_pins)
        if (pin.path == room.path)
            return pin.path;
    return QString();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── pins ────────────────────────────────────────────────────────────────────────────

QStringList PlacesModel::iconChoices() const
{
    return {QStringLiteral("folder"), QStringLiteral("home"), QStringLiteral("star"), QStringLiteral("heart"), QStringLiteral("bookmark"), QStringLiteral("flag"),
            QStringLiteral("code"), QStringLiteral("terminal"), QStringLiteral("cpu"), QStringLiteral("flask"), QStringLiteral("briefcase"), QStringLiteral("book"),
            QStringLiteral("document"), QStringLiteral("download"), QStringLiteral("image"), QStringLiteral("camera"), QStringLiteral("palette"), QStringLiteral("audio"),
            QStringLiteral("video"), QStringLiteral("gamepad"), QStringLiteral("cloud"), QStringLiteral("globe"), QStringLiteral("package"), QStringLiteral("archive"),
            QStringLiteral("bolt"), QStringLiteral("leaf"), QStringLiteral("lock"), QStringLiteral("user"), QStringLiteral("mail"), QStringLiteral("calendar"),
            QStringLiteral("drive"), QStringLiteral("root"), QStringLiteral("trash")};
}

QString PlacesModel::defaultIconFor(const QString &key) const
{
    static const QHash<QString, QString> icons = {
        {QStringLiteral("home"), QStringLiteral("home")}, {QStringLiteral("downloads"), QStringLiteral("download")}, {QStringLiteral("documents"), QStringLiteral("document")},
        {QStringLiteral("pictures"), QStringLiteral("image")}, {QStringLiteral("music"), QStringLiteral("audio")}, {QStringLiteral("videos"), QStringLiteral("video")},
        {QStringLiteral("system"), QStringLiteral("root")}, {QStringLiteral("trash"), QStringLiteral("trash")}, {QStringLiteral("drive"), QStringLiteral("drive")},
    };
    return icons.value(key, QStringLiteral("folder"));
}

int PlacesModel::groupOf(const Place &place) const
{
    if (place.section != QLatin1String("pinned"))
        return 2;
    if (place.path == QLatin1String("trash:///"))
        return 2;
    const Place room = roomFor(place.path);
    if (room.path == place.path && (room.key == QLatin1String("home") || room.key == QLatin1String("downloads") || room.key == QLatin1String("system")))
        return 0;
    return 1;
}

void PlacesModel::loadPins()
{
    QSettings settings(QStringLiteral("vados"), QStringLiteral("files"));
    const QJsonArray stored = QJsonDocument::fromJson(settings.value(PINS_KEY).toByteArray()).array();
    m_pins.clear();
    if (settings.contains(PINS_KEY)) {
        for (const QJsonValue &value : stored) {
            const QJsonObject object = value.toObject();
            Place pin{object.value(QStringLiteral("name")).toString(), object.value(QStringLiteral("path")).toString(), QString(), QStringLiteral("pinned")};
            pin.icon = object.value(QStringLiteral("icon")).toString(QStringLiteral("folder"));
            pin.key = roomFor(pin.path).key;
            pin.tint = object.value(QStringLiteral("tint")).toString();
            pin.isMounted = pin.path == QLatin1String("trash:///") || QFileInfo(pin.path).isDir();
            m_pins.append(pin);
        }
        std::stable_sort(m_pins.begin(), m_pins.end(), [this](const Place &a, const Place &b) { return groupOf(a) < groupOf(b); });
        return;
    }
    // First run: the rooms, then whatever GTK bookmarks already exist, so nothing the user had is lost.
    for (const Place &room : m_rooms) {
        Place pin = room;
        pin.section = QStringLiteral("pinned");
        pin.icon = defaultIconFor(room.key);
        m_pins.append(pin);
    }
    QFile file(bookmarksFile());
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            const QUrl url(line.section(QLatin1Char(' '), 0, 0));
            if (!url.isLocalFile() || isPinned(url.toLocalFile()))
                continue;
            const QString path = url.toLocalFile();
            const QString label = line.section(QLatin1Char(' '), 1);
            Place pin{label.isEmpty() ? QFileInfo(path).fileName() : label, path, roomFor(path).key, QStringLiteral("pinned")};
            pin.icon = QStringLiteral("bookmark");
            pin.isMounted = QFileInfo(path).isDir();
            // The trash stays last, where it was.
            m_pins.insert(m_pins.size() - 1, pin);
        }
    }
    std::stable_sort(m_pins.begin(), m_pins.end(), [this](const Place &a, const Place &b) { return groupOf(a) < groupOf(b); });
    savePins();
}

void PlacesModel::savePins() const
{
    QJsonArray stored;
    for (const Place &pin : m_pins)
        stored.append(QJsonObject{{QStringLiteral("name"), pin.name}, {QStringLiteral("path"), pin.path}, {QStringLiteral("icon"), pin.icon}, {QStringLiteral("tint"), pin.tint}});
    QSettings settings(QStringLiteral("vados"), QStringLiteral("files"));
    settings.setValue(PINS_KEY, QJsonDocument(stored).toJson(QJsonDocument::Compact));
}

bool PlacesModel::isPinned(const QString &path) const
{
    for (const Place &pin : m_pins)
        if (pin.path == path)
            return true;
    return false;
}

void PlacesModel::pin(const QString &path, int row)
{
    if (path.isEmpty() || isPinned(path))
        return;
    const Place room = roomFor(path);
    Place pin{path == QLatin1String("/") ? QStringLiteral("System") : QFileInfo(path).fileName(), path, room.key, QStringLiteral("pinned")};
    pin.icon = room.path == path ? defaultIconFor(room.key) : QStringLiteral("folder");
    pin.isMounted = true;
    // A new pin goes to the end of its own run, so the dividers stay put.
    const int group = groupOf(pin);
    int at = 0;
    while (at < m_pins.size() && groupOf(m_pins.at(at)) <= group)
        ++at;
    Q_UNUSED(row)
    beginInsertRows(QModelIndex(), at, at);
    m_pins.insert(at, pin);
    m_places.insert(at, pin);
    endInsertRows();
    savePins();
    emit pinsChanged();
}

void PlacesModel::unpin(const QString &path)
{
    for (int row = 0; row < m_pins.size(); ++row) {
        if (m_pins.at(row).path != path)
            continue;
        beginRemoveRows(QModelIndex(), row, row);
        m_pins.removeAt(row);
        m_places.removeAt(row);
        endRemoveRows();
        savePins();
        emit pinsChanged();
        return;
    }
}

void PlacesModel::movePin(int from, int to)
{
    if (from == to || from < 0 || to < 0 || from >= m_pins.size() || to >= m_pins.size())
        return;
    // A pin stays inside its own run.
    if (groupOf(m_pins.at(from)) != groupOf(m_pins.at(to)))
        return;
    // Qt's move index is the row the item lands before, counted before it is taken out.
    beginMoveRows(QModelIndex(), from, from, QModelIndex(), to > from ? to + 1 : to);
    m_pins.move(from, to);
    m_places.move(from, to);
    endMoveRows();
    savePins();
}

void PlacesModel::renamePin(int row, const QString &name)
{
    const QString trimmed = name.trimmed();
    if (row < 0 || row >= m_pins.size() || trimmed.isEmpty())
        return;
    m_pins[row].name = trimmed;
    m_places[row].name = trimmed;
    emit dataChanged(index(row), index(row), {NameRole});
    savePins();
}

void PlacesModel::setPinIcon(int row, const QString &icon)
{
    if (row < 0 || row >= m_pins.size())
        return;
    m_pins[row].icon = icon;
    m_places[row].icon = icon;
    emit dataChanged(index(row), index(row), {IconRole});
    savePins();
}

void PlacesModel::setPinTint(int row, const QString &tint)
{
    if (row < 0 || row >= m_pins.size())
        return;
    m_pins[row].tint = tint;
    m_places[row].tint = tint;
    emit dataChanged(index(row), index(row), {AccentKeyRole});
    savePins();
    emit pinsChanged();
}

QString PlacesModel::tintFor(const QString &path) const
{
    QString best;
    int bestLength = -1;
    for (const Place &pin : m_pins) {
        if (pin.tint.isEmpty() || pin.path.size() <= bestLength)
            continue;
        const bool isInside = pin.path == path || (pin.path.size() > 1 && path.startsWith(pin.path + QLatin1Char('/')));
        if (isInside) {
            best = pin.tint;
            bestLength = int(pin.path.size());
        }
    }
    return best;
}

QString PlacesModel::tintAt(int row) const
{
    return row >= 0 && row < m_pins.size() ? m_pins.at(row).tint : QString();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── drives ──────────────────────────────────────────────────────────────────────────

void PlacesModel::refreshDrives()
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process] {
        process->deleteLater();
        const QJsonArray devices = QJsonDocument::fromJson(process->readAllStandardOutput()).object().value(QStringLiteral("blockdevices")).toArray();
        QList<Place> drives;
        std::function<void(const QJsonArray &, const QString &, bool)> walk = [&](const QJsonArray &nodes, const QString &model, bool isRemovable) {
            for (const QJsonValue &value : nodes) {
                const QJsonObject node = value.toObject();
                const QString nodeModel = node.value(QStringLiteral("model")).toString(model).trimmed();
                const bool nodeRemovable = isRemovable || node.value(QStringLiteral("hotplug")).toBool() || node.value(QStringLiteral("rm")).toBool();
                if (node.contains(QStringLiteral("children")))
                    walk(node.value(QStringLiteral("children")).toArray(), nodeModel, nodeRemovable);
                const QString fileSystem = node.value(QStringLiteral("fstype")).toString();
                const QString mountPoint = node.value(QStringLiteral("mountpoint")).toString();
                if (fileSystem.isEmpty() || fileSystem == QLatin1String("swap") || fileSystem.startsWith(QLatin1String("crypto")) || fileSystem == QLatin1String("LVM2_member") || isSystemMount(mountPoint))
                    continue;
                if (node.value(QStringLiteral("type")).toString() == QLatin1String("loop"))
                    continue;
                Place drive;
                const qint64 size = node.value(QStringLiteral("size")).toVariant().toLongLong();
                const QString label = node.value(QStringLiteral("label")).toString();
                const QString sizeText = QLocale::c().formattedDataSize(size, 0, QLocale::DataSizeSIFormat);
                drive.name = !label.isEmpty() ? label : !nodeModel.isEmpty() && nodeModel != QLatin1String("MassStorageClass") ? nodeModel : sizeText + QStringLiteral(" volume");
                drive.device = node.value(QStringLiteral("path")).toString();
                drive.path = mountPoint;
                drive.isMounted = !mountPoint.isEmpty();
                drive.canEject = nodeRemovable;
                drive.key = QStringLiteral("drive");
                drive.icon = QStringLiteral("drive");
                drive.section = QStringLiteral("drives");
                if (drive.isMounted) {
                    const QStorageInfo storage(mountPoint);
                    if (storage.bytesTotal() > 0) {
                        drive.usage = 1.0 - double(storage.bytesAvailable()) / double(storage.bytesTotal());
                        drive.detail = QLocale::c().formattedDataSize(storage.bytesAvailable(), 0, QLocale::DataSizeSIFormat) + QStringLiteral(" free");
                    }
                } else {
                    drive.detail = sizeText + QStringLiteral(" · not mounted");
                }
                drives.append(drive);
            }
        };
        walk(devices, QString(), false);
        bool isSame = drives.size() == m_drives.size();
        for (int index = 0; isSame && index < drives.size(); ++index)
            isSame = drives.at(index).device == m_drives.at(index).device && drives.at(index).path == m_drives.at(index).path && drives.at(index).detail == m_drives.at(index).detail;
        if (isSame)
            return;
        m_drives = drives;
        rebuild();
    });
    process->start(QStringLiteral("lsblk"), {QStringLiteral("-J"), QStringLiteral("-b"), QStringLiteral("-o"), QStringLiteral("NAME,PATH,LABEL,SIZE,MOUNTPOINT,FSTYPE,TYPE,HOTPLUG,RM,MODEL")});
}

void PlacesModel::mount(const QString &device)
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, device](int exitCode) {
        process->deleteLater();
        const QString output = QString::fromUtf8(process->readAllStandardOutput());
        if (exitCode != 0) {
            emit failed(QStringLiteral("mount: ") + QString::fromUtf8(process->readAllStandardError()).trimmed().section(QLatin1Char('\n'), 0, 0));
            return;
        }
        // "Mounted /dev/sdb1 at /run/media/user/LABEL" is the only place udisksctl says where it went.
        const QRegularExpressionMatch match = QRegularExpression(QStringLiteral(" at (.+)$")).match(output.trimmed());
        refreshDrives();
        if (match.hasMatch())
            emit mounted(device, match.captured(1).remove(QRegularExpression(QStringLiteral("\\.$"))));
    });
    process->start(QStringLiteral("udisksctl"), {QStringLiteral("mount"), QStringLiteral("--no-user-interaction"), QStringLiteral("-b"), device});
}

void PlacesModel::unmount(const QString &device)
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int exitCode) {
        process->deleteLater();
        if (exitCode != 0)
            emit failed(QStringLiteral("eject: ") + QString::fromUtf8(process->readAllStandardError()).trimmed().section(QLatin1Char('\n'), 0, 0));
        refreshDrives();
    });
    process->start(QStringLiteral("udisksctl"), {QStringLiteral("unmount"), QStringLiteral("--no-user-interaction"), QStringLiteral("-b"), device});
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
