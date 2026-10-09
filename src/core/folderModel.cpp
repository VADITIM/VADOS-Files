#include "folderModel.h"

#include <QCollator>
#include <QDirIterator>
#include <QLocale>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>

namespace {

const QString TRASH_PATH = QStringLiteral("trash:///");
// A search that has found this many is no longer a search, it is a listing of the disk; stop so the view stays usable.
constexpr int SEARCH_RESULT_CEILING = 5000;
constexpr int SEARCH_BATCH = 48;

QString trashRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash");
}

QString formatSize(qint64 bytes)
{
    return QLocale::c().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

QString formatModified(const QDateTime &modified)
{
    if (!modified.isValid())
        return QString();
    const QDate today = QDate::currentDate();
    const QLocale locale = QLocale::c();
    if (modified.date() == today)
        return locale.toString(modified, QStringLiteral("HH:mm"));
    if (modified.date() == today.addDays(-1))
        return QStringLiteral("Yesterday ") + locale.toString(modified, QStringLiteral("HH:mm"));
    if (modified.date().year() == today.year())
        return locale.toString(modified, QStringLiteral("d MMM HH:mm"));
    return locale.toString(modified, QStringLiteral("d MMM yyyy"));
}

QList<FileEntry> readFolder(const QString &path, QString *error)
{
    QList<FileEntry> entries;
    QDir directory(path);
    if (!directory.exists()) {
        *error = QStringLiteral("folder does not exist");
        return entries;
    }
    if (!directory.isReadable()) {
        *error = QStringLiteral("no permission to read this folder");
        return entries;
    }
    const QMimeDatabase mimeDatabase;
    const QFileInfoList infos = directory.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    entries.reserve(infos.size());
    for (const QFileInfo &info : infos)
        entries.append(entryFromInfo(info, mimeDatabase, true));
    return entries;
}

QList<FileEntry> readTrash()
{
    QList<FileEntry> entries;
    const QString root = trashRoot();
    const QMimeDatabase mimeDatabase;
    const QFileInfoList infos = QDir(root + QStringLiteral("/files")).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    for (const QFileInfo &info : infos) {
        FileEntry entry = entryFromInfo(info, mimeDatabase, true);
        // The trash keeps the original location in a sidecar file, percent-encoded by the spec.
        QSettings trashInfo(root + QStringLiteral("/info/") + info.fileName() + QStringLiteral(".trashinfo"), QSettings::IniFormat);
        trashInfo.beginGroup(QStringLiteral("Trash Info"));
        entry.originalPath = QUrl::fromPercentEncoding(trashInfo.value(QStringLiteral("Path")).toString().toUtf8());
        entry.deletedAt = QDateTime::fromString(trashInfo.value(QStringLiteral("DeletionDate")).toString(), Qt::ISODate);
        entry.isHidden = false;
        entries.append(entry);
    }
    return entries;
}

} // namespace

// #region ── lifecycle ───────────────────────────────────────────────────────────────────────

FolderModel::FolderModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_refreshDebounce.setSingleShot(true);
    m_refreshDebounce.setInterval(140);
    connect(&m_refreshDebounce, &QTimer::timeout, this, &FolderModel::refresh);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        if (m_mode != QLatin1String("search"))
            m_refreshDebounce.start();
    });
}

FolderModel::~FolderModel()
{
    if (m_searchCancel)
        m_searchCancel->store(true);
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── model ───────────────────────────────────────────────────────────────────────────

int FolderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant FolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const FileEntry &entry = m_rows.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole: return entry.name;
    case PathRole: return entry.path;
    case UrlRole: return QUrl::fromLocalFile(entry.path);
    case IsDirectoryRole: return entry.isDirectory;
    case IsHiddenRole: return entry.isHidden;
    case IsSymlinkRole: return entry.isSymlink;
    case SizeRole: return entry.size;
    case SizeTextRole:
        if (entry.isDirectory)
            return entry.childCount < 0 ? QString() : entry.childCount == 1 ? QStringLiteral("1 item") : QStringLiteral("%1 items").arg(entry.childCount);
        return formatSize(entry.size);
    case ModifiedRole: return entry.modified;
    case ModifiedTextRole: return formatModified(entry.modified);
    case MimeTypeRole: return entry.mimeType;
    case KindRole: return entry.kind;
    case SuffixRole: return entry.suffix;
    case ChildCountRole: return entry.childCount;
    case IsSelectedRole: return m_selected.contains(entry.path);
    case IsCutRole: return m_cutPaths.contains(entry.path);
    case OriginalPathRole: return entry.originalPath;
    case DeletedAtTextRole: return formatModified(entry.deletedAt);
    case CanThumbnailRole: return entry.kind == QLatin1String("image") || entry.kind == QLatin1String("video");
    }
    return {};
}

QHash<int, QByteArray> FolderModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {UrlRole, "url"},
        {IsDirectoryRole, "isDirectory"},
        {IsHiddenRole, "isHidden"},
        {IsSymlinkRole, "isSymlink"},
        {SizeRole, "size"},
        {SizeTextRole, "sizeText"},
        {ModifiedRole, "modified"},
        {ModifiedTextRole, "modifiedText"},
        {MimeTypeRole, "mimeType"},
        {KindRole, "kind"},
        {SuffixRole, "suffix"},
        {ChildCountRole, "childCount"},
        {IsSelectedRole, "isSelected"},
        {IsCutRole, "isCut"},
        {OriginalPathRole, "originalPath"},
        {DeletedAtTextRole, "deletedAtText"},
        {CanThumbnailRole, "canThumbnail"},
    };
}

int FolderModel::folderCount() const
{
    return int(std::count_if(m_rows.cbegin(), m_rows.cend(), [](const FileEntry &entry) { return entry.isDirectory; }));
}

qint64 FolderModel::totalSize() const
{
    qint64 total = 0;
    for (const FileEntry &entry : m_rows)
        total += entry.size;
    return total;
}

qint64 FolderModel::selectedSize() const
{
    qint64 total = 0;
    for (const FileEntry &entry : m_rows)
        if (m_selected.contains(entry.path))
            total += entry.size;
    return total;
}

QVariantMap FolderModel::get(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_rows.size())
        return map;
    const QModelIndex modelIndex = index(row);
    const auto roles = roleNames();
    for (auto iterator = roles.cbegin(); iterator != roles.cend(); ++iterator)
        map.insert(QString::fromUtf8(iterator.value()), data(modelIndex, iterator.key()));
    return map;
}

int FolderModel::indexOfPath(const QString &path) const
{
    for (int row = 0; row < m_rows.size(); ++row)
        if (m_rows.at(row).path == path)
            return row;
    return -1;
}

int FolderModel::indexOfPrefix(const QString &prefix, int from) const
{
    if (prefix.isEmpty() || m_rows.isEmpty())
        return -1;
    const int count = int(m_rows.size());
    for (int offset = 0; offset < count; ++offset) {
        const int row = (qMax(0, from) + offset) % count;
        if (m_rows.at(row).name.startsWith(prefix, Qt::CaseInsensitive))
            return row;
    }
    return -1;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── loading ─────────────────────────────────────────────────────────────────────────

void FolderModel::load(const QString &path)
{
    cancelSearch();
    QString cleanPath = path == TRASH_PATH ? path : QDir::cleanPath(path);
    m_pendingPath = cleanPath;
    emit pendingPathChanged();
    startRead(cleanPath, false);
}

void FolderModel::refresh()
{
    if (m_path.isEmpty() || m_mode == QLatin1String("search"))
        return;
    if (m_path != TRASH_PATH && !QFileInfo::exists(m_path)) {
        emit pathLost(m_path);
        return;
    }
    startRead(m_path, true);
}

void FolderModel::startRead(const QString &path, bool isRefresh)
{
    const int generation = ++m_generation;
    if (!isRefresh)
        setLoading(true);
    QPointer<FolderModel> guard(this);
    auto future = QtConcurrent::run([path] {
        QString error;
        QList<FileEntry> entries = path == TRASH_PATH ? readTrash() : readFolder(path, &error);
        return std::make_pair(entries, error);
    });
    future.then(this, [this, guard, generation, path, isRefresh](std::pair<QList<FileEntry>, QString> result) {
        if (guard)
            finishRead(generation, path, std::move(result.first), result.second, isRefresh);
    });
}

void FolderModel::finishRead(int generation, const QString &path, QList<FileEntry> entries, const QString &error, bool isRefresh)
{
    // A read that a newer navigation has overtaken is dropped rather than applied, or a fast double-click lands in the folder clicked first.
    if (generation != m_generation)
        return;
    if (isRefresh) {
        m_all = entries;
        applyDiff(visibleSorted(m_all));
        return;
    }
    m_pending = std::move(entries);
    m_pendingError = error;
    m_hasPending = true;
    setLoading(false);
    emit loaded(path);
}

void FolderModel::commit()
{
    if (!m_hasPending)
        return;
    m_hasPending = false;
    beginResetModel();
    m_all = std::move(m_pending);
    m_pending.clear();
    m_path = m_pendingPath;
    m_mode = m_path == TRASH_PATH ? QStringLiteral("trash") : QStringLiteral("folder");
    m_filter.clear();
    m_rows = visibleSorted(m_all);
    m_selected.clear();
    m_currentIndex = m_rows.isEmpty() ? -1 : 0;
    endResetModel();
    if (m_error != m_pendingError) {
        m_error = m_pendingError;
        emit errorChanged();
    }
    rewatch();
    emit pathChanged();
    emit filterChanged();
    emit countChanged();
    emit selectionChanged();
    emit currentIndexChanged();
}

void FolderModel::rewatch()
{
    const QStringList watched = m_watcher.directories();
    if (!watched.isEmpty())
        m_watcher.removePaths(watched);
    const QString target = m_mode == QLatin1String("trash") ? trashRoot() + QStringLiteral("/files") : m_path;
    if (QFileInfo(target).isDir())
        m_watcher.addPath(target);
}

void FolderModel::setLoading(bool isLoading)
{
    if (m_isLoading == isLoading)
        return;
    m_isLoading = isLoading;
    emit isLoadingChanged();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── search ──────────────────────────────────────────────────────────────────────────

void FolderModel::search(const QString &query)
{
    cancelSearch();
    const QString trimmed = query.trimmed();
    if (trimmed.isEmpty() || m_mode == QLatin1String("trash"))
        return;
    m_searchQuery = trimmed;
    beginResetModel();
    m_all.clear();
    m_rows.clear();
    m_selected.clear();
    m_currentIndex = -1;
    m_mode = QStringLiteral("search");
    m_filter.clear();
    endResetModel();
    emit pathChanged();
    emit countChanged();
    emit selectionChanged();
    m_isSearching = true;
    emit isSearchingChanged();

    auto isCancelled = std::make_shared<std::atomic_bool>(false);
    m_searchCancel = isCancelled;
    const int generation = ++m_generation;
    const QString root = m_path;
    const bool shouldIncludeHidden = m_showHidden;
    QPointer<FolderModel> guard(this);

    auto deliver = [guard, generation](QList<FileEntry> batch, bool isDone) {
        QMetaObject::invokeMethod(guard.data(), [guard, generation, batch = std::move(batch), isDone] {
            if (!guard || guard->m_generation != generation)
                return;
            if (!batch.isEmpty()) {
                // Results arrive in walk order and are inserted where they sort, so the grid grows in place rather than reshuffling under the pointer.
                for (const FileEntry &entry : batch) {
                    guard->m_all.append(entry);
                    const auto position = std::lower_bound(guard->m_rows.begin(), guard->m_rows.end(), entry,
                        [&](const FileEntry &left, const FileEntry &right) { return guard->lessThan(left, right); });
                    const int row = int(position - guard->m_rows.begin());
                    guard->beginInsertRows(QModelIndex(), row, row);
                    guard->m_rows.insert(row, entry);
                    guard->endInsertRows();
                }
                emit guard->countChanged();
            }
            if (isDone) {
                guard->m_isSearching = false;
                emit guard->isSearchingChanged();
            }
        }, Qt::QueuedConnection);
    };

    (void)QtConcurrent::run([root, trimmed, shouldIncludeHidden, isCancelled, deliver] {
        const QMimeDatabase mimeDatabase;
        QDirIterator::IteratorFlags flags = QDirIterator::Subdirectories;
        QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System;
        if (shouldIncludeHidden)
            filters |= QDir::Hidden;
        QDirIterator iterator(root, filters, flags);
        QList<FileEntry> batch;
        int found = 0;
        while (iterator.hasNext() && !isCancelled->load()) {
            iterator.next();
            const QFileInfo info = iterator.fileInfo();
            if (!info.fileName().contains(trimmed, Qt::CaseInsensitive))
                continue;
            batch.append(entryFromInfo(info, mimeDatabase, false));
            if (++found >= SEARCH_RESULT_CEILING)
                break;
            if (batch.size() >= SEARCH_BATCH) {
                deliver(std::move(batch), false);
                batch = {};
            }
        }
        if (!isCancelled->load())
            deliver(std::move(batch), true);
    });
}

void FolderModel::cancelSearch()
{
    if (m_searchCancel) {
        m_searchCancel->store(true);
        m_searchCancel.reset();
    }
    if (m_isSearching) {
        m_isSearching = false;
        emit isSearchingChanged();
    }
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── sorting and filtering ───────────────────────────────────────────────────────────

bool FolderModel::passesFilter(const FileEntry &entry) const
{
    if (!m_showHidden && entry.isHidden && m_mode != QLatin1String("search"))
        return false;
    if (!m_filter.isEmpty() && !entry.name.contains(m_filter, Qt::CaseInsensitive))
        return false;
    if (entry.isDirectory)
        return true;
    if (m_isFoldersOnly)
        return false;
    return m_namePatterns.isEmpty() || std::any_of(m_namePatterns.cbegin(), m_namePatterns.cend(), [&entry](const QRegularExpression &pattern) { return pattern.match(entry.name).hasMatch(); });
}

bool FolderModel::lessThan(const FileEntry &left, const FileEntry &right) const
{
    // Hidden entries lead the list, above the folders, whatever the sort.
    if (left.isHidden != right.isHidden)
        return left.isHidden;
    if (m_foldersFirst && left.isDirectory != right.isDirectory)
        return left.isDirectory;
    static thread_local QCollator collator = [] {
        QCollator created(QLocale::c());
        created.setNumericMode(true);
        created.setCaseSensitivity(Qt::CaseInsensitive);
        return created;
    }();
    int comparison = 0;
    if (m_sortKey == QLatin1String("size"))
        comparison = left.isDirectory && right.isDirectory ? left.childCount - right.childCount : (left.size < right.size ? -1 : left.size > right.size ? 1 : 0);
    else if (m_sortKey == QLatin1String("modified"))
        comparison = left.modified < right.modified ? -1 : left.modified > right.modified ? 1 : 0;
    else if (m_sortKey == QLatin1String("kind"))
        comparison = collator.compare(left.kind + left.suffix, right.kind + right.suffix);
    if (comparison == 0)
        comparison = collator.compare(left.name, right.name);
    if (comparison == 0)
        comparison = QString::compare(left.path, right.path);
    return m_sortDescending ? comparison > 0 : comparison < 0;
}

QList<FileEntry> FolderModel::visibleSorted(const QList<FileEntry> &source) const
{
    QList<FileEntry> rows;
    rows.reserve(source.size());
    for (const FileEntry &entry : source)
        if (passesFilter(entry))
            rows.append(entry);
    std::sort(rows.begin(), rows.end(), [this](const FileEntry &left, const FileEntry &right) { return lessThan(left, right); });
    return rows;
}

void FolderModel::resort()
{
    const QString currentPath = m_currentIndex >= 0 && m_currentIndex < m_rows.size() ? m_rows.at(m_currentIndex).path : QString();
    beginResetModel();
    m_rows = visibleSorted(m_all);
    endResetModel();
    m_currentIndex = currentPath.isEmpty() ? (m_rows.isEmpty() ? -1 : 0) : indexOfPath(currentPath);
    emit currentIndexChanged();
    emit countChanged();
}

// Rows that stayed keep their delegates, so the view can animate what came and went instead of rebuilding — a file appearing pops in where it sorts rather than the whole folder flashing.
void FolderModel::applyDiff(const QList<FileEntry> &next)
{
    const QString currentPath = m_currentIndex >= 0 && m_currentIndex < m_rows.size() ? m_rows.at(m_currentIndex).path : QString();
    QSet<QString> nextPaths;
    nextPaths.reserve(next.size());
    for (const FileEntry &entry : next)
        nextPaths.insert(entry.path);

    for (int row = int(m_rows.size()) - 1; row >= 0; --row) {
        if (nextPaths.contains(m_rows.at(row).path))
            continue;
        int first = row;
        while (first > 0 && !nextPaths.contains(m_rows.at(first - 1).path))
            --first;
        beginRemoveRows(QModelIndex(), first, row);
        m_rows.remove(first, row - first + 1);
        endRemoveRows();
        row = first;
    }

    QHash<QString, int> nextOrder;
    for (int index = 0; index < next.size(); ++index)
        nextOrder.insert(next.at(index).path, index);
    int lastOrder = -1;
    bool isSubsequence = true;
    QSet<QString> remaining;
    for (const FileEntry &entry : std::as_const(m_rows)) {
        const int order = nextOrder.value(entry.path);
        if (order < lastOrder) {
            isSubsequence = false;
            break;
        }
        lastOrder = order;
        remaining.insert(entry.path);
    }
    if (!isSubsequence) {
        // A change that reordered what stayed (a file grew past its neighbour under a size sort) has no insert/remove story to tell; rebuild.
        beginResetModel();
        m_rows = next;
        endResetModel();
    } else {
        for (int index = 0; index < next.size(); ++index) {
            if (index < m_rows.size() && m_rows.at(index).path == next.at(index).path) {
                const FileEntry &incoming = next.at(index);
                FileEntry &existing = m_rows[index];
                if (existing.size != incoming.size || existing.modified != incoming.modified || existing.childCount != incoming.childCount || existing.kind != incoming.kind) {
                    existing = incoming;
                    emit dataChanged(this->index(index), this->index(index));
                }
                continue;
            }
            int end = index;
            while (end + 1 < next.size() && !remaining.contains(next.at(end + 1).path))
                ++end;
            beginInsertRows(QModelIndex(), index, end);
            for (int insert = index; insert <= end; ++insert)
                m_rows.insert(insert, next.at(insert));
            endInsertRows();
            index = end;
        }
    }

    bool hasSelectionChanged = false;
    for (auto iterator = m_selected.begin(); iterator != m_selected.end();) {
        if (!nextPaths.contains(*iterator)) {
            iterator = m_selected.erase(iterator);
            hasSelectionChanged = true;
        } else {
            ++iterator;
        }
    }
    const int nextCurrent = currentPath.isEmpty() ? -1 : indexOfPath(currentPath);
    if (nextCurrent != m_currentIndex) {
        m_currentIndex = nextCurrent >= 0 ? nextCurrent : qMin(m_currentIndex, int(m_rows.size()) - 1);
        emit currentIndexChanged();
    }
    emit countChanged();
    if (hasSelectionChanged)
        emit selectionChanged();
}

void FolderModel::setSortKey(const QString &key)
{
    if (m_sortKey == key)
        return;
    m_sortKey = key;
    resort();
    emit sortChanged();
}

void FolderModel::setSortDescending(bool isDescending)
{
    if (m_sortDescending == isDescending)
        return;
    m_sortDescending = isDescending;
    resort();
    emit sortChanged();
}

void FolderModel::setFoldersFirst(bool isFirst)
{
    if (m_foldersFirst == isFirst)
        return;
    m_foldersFirst = isFirst;
    resort();
    emit sortChanged();
}

void FolderModel::setShowHidden(bool isShown)
{
    if (m_showHidden == isShown)
        return;
    m_showHidden = isShown;
    applyDiff(visibleSorted(m_all));
    emit showHiddenChanged();
}

void FolderModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    applyDiff(visibleSorted(m_all));
    emit filterChanged();
}

void FolderModel::setNameFilters(const QStringList &filters)
{
    if (m_nameFilters == filters)
        return;
    m_nameFilters = filters;
    m_namePatterns.clear();
    for (const QString &filter : filters)
        m_namePatterns.append(QRegularExpression(QRegularExpression::wildcardToRegularExpression(filter), QRegularExpression::CaseInsensitiveOption));
    applyDiff(visibleSorted(m_all));
    emit nameFiltersChanged();
}

void FolderModel::setFoldersOnly(bool isFoldersOnly)
{
    if (m_isFoldersOnly == isFoldersOnly)
        return;
    m_isFoldersOnly = isFoldersOnly;
    applyDiff(visibleSorted(m_all));
    emit nameFiltersChanged();
}

void FolderModel::setCutPaths(const QStringList &paths)
{
    if (m_cutPaths == paths)
        return;
    m_cutPaths = paths;
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(int(m_rows.size()) - 1), {IsCutRole});
    emit cutPathsChanged();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── selection ───────────────────────────────────────────────────────────────────────

void FolderModel::emitSelectionRoles()
{
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(int(m_rows.size()) - 1), {IsSelectedRole});
    emit selectionChanged();
}

void FolderModel::setCurrentIndex(int index)
{
    if (m_currentIndex == index)
        return;
    m_currentIndex = index;
    emit currentIndexChanged();
}

void FolderModel::select(int row)
{
    m_selected.clear();
    if (row >= 0 && row < m_rows.size())
        m_selected.insert(m_rows.at(row).path);
    setCurrentIndex(row);
    emitSelectionRoles();
}

void FolderModel::toggle(int row)
{
    if (row < 0 || row >= m_rows.size())
        return;
    const QString &path = m_rows.at(row).path;
    if (!m_selected.remove(path))
        m_selected.insert(path);
    setCurrentIndex(row);
    emitSelectionRoles();
}

void FolderModel::selectRange(int from, int to, bool isAdditive)
{
    if (!isAdditive)
        m_selected.clear();
    const int first = qMax(0, qMin(from, to));
    const int last = qMin(int(m_rows.size()) - 1, qMax(from, to));
    for (int row = first; row <= last; ++row)
        m_selected.insert(m_rows.at(row).path);
    setCurrentIndex(to);
    emitSelectionRoles();
}

void FolderModel::selectRows(const QVariantList &rows, const QStringList &basePaths)
{
    QSet<QString> next(basePaths.cbegin(), basePaths.cend());
    for (const QVariant &value : rows) {
        const int row = value.toInt();
        if (row >= 0 && row < m_rows.size())
            next.insert(m_rows.at(row).path);
    }
    if (next == m_selected)
        return;
    m_selected = next;
    emitSelectionRoles();
}

void FolderModel::selectPaths(const QStringList &paths)
{
    m_selected.clear();
    int first = -1;
    for (const QString &path : paths) {
        const int row = indexOfPath(path);
        if (row < 0)
            continue;
        m_selected.insert(path);
        if (first < 0 || row < first)
            first = row;
    }
    if (first >= 0)
        setCurrentIndex(first);
    emitSelectionRoles();
}

void FolderModel::selectAll()
{
    for (const FileEntry &entry : std::as_const(m_rows))
        m_selected.insert(entry.path);
    emitSelectionRoles();
}

void FolderModel::clearSelection()
{
    if (m_selected.isEmpty())
        return;
    m_selected.clear();
    emitSelectionRoles();
}

bool FolderModel::isSelected(int row) const
{
    return row >= 0 && row < m_rows.size() && m_selected.contains(m_rows.at(row).path);
}

QStringList FolderModel::selectedPaths() const
{
    QStringList paths;
    for (const FileEntry &entry : m_rows)
        if (m_selected.contains(entry.path))
            paths.append(entry.path);
    return paths;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
