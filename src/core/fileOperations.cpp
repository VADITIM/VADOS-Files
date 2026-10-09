#include "fileOperations.h"

#include <algorithm>

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QTimer>
#include <QUrl>
#include <QtConcurrent/QtConcurrentRun>

namespace {

constexpr qint64 CHUNK_BYTES = 1 << 20;
constexpr qint64 REPORT_INTERVAL_MS = 60;
// Long enough for the bar to be seen full before its row leaves; mirrored by nothing, the row's exit is its own animation.
constexpr int FINISHED_ROW_LINGER_MS = 900;

QString trashRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/Trash");
}

qint64 measure(const QString &path)
{
    const QFileInfo info(path);
    if (info.isSymLink() || !info.isDir())
        return info.isSymLink() ? 0 : info.size();
    qint64 total = 0;
    QDirIterator iterator(path, QDir::Files | QDir::Hidden | QDir::System | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        iterator.next();
        total += iterator.fileInfo().size();
    }
    return total;
}

QString displayName(const QString &path)
{
    if (path == QDir::homePath())
        return QStringLiteral("Home");
    const QString name = QFileInfo(path).fileName();
    return name.isEmpty() ? path : name;
}

QString countText(int count)
{
    return count == 1 ? QStringLiteral("1 item") : QStringLiteral("%1 items").arg(count);
}

bool removePath(const QString &path)
{
    const QFileInfo info(path);
    if (info.isDir() && !info.isSymLink())
        return QDir(path).removeRecursively();
    return QFile::remove(path);
}

} // namespace

// #region ── job model ───────────────────────────────────────────────────────────────────────

int JobModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_jobs.size());
}

QVariant JobModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_jobs.size())
        return {};
    const auto &job = m_jobs.at(index.row());
    QMutexLocker locker(&job->mutex);
    switch (role) {
    case JobIdRole: return job->id;
    case VerbRole: return job->verb;
    case TitleRole: return job->title;
    case DetailRole: return job->detail;
    case ProgressRole: {
        if (job->state == QLatin1String("done"))
            return 1.0;
        if (job->isIndeterminate)
            return -1.0;
        const qint64 total = job->totalBytes.load();
        if (total > 0)
            return double(job->doneBytes.load()) / double(total);
        return job->items.isEmpty() ? 0.0 : double(job->doneCount.load()) / double(job->items.size());
    }
    case StateRole: return job->state;
    case ConflictNameRole: return job->conflictName;
    case ErrorRole: return job->error;
    }
    return {};
}

QHash<int, QByteArray> JobModel::roleNames() const
{
    return {{JobIdRole, "jobId"}, {VerbRole, "verb"}, {TitleRole, "title"}, {DetailRole, "detail"},
            {ProgressRole, "progress"}, {StateRole, "state"}, {ConflictNameRole, "conflictName"}, {ErrorRole, "error"}};
}

void JobModel::add(const std::shared_ptr<Job> &job)
{
    beginInsertRows(QModelIndex(), int(m_jobs.size()), int(m_jobs.size()));
    m_jobs.append(job);
    endInsertRows();
    emit countChanged();
}

void JobModel::update(int jobId)
{
    for (int row = 0; row < m_jobs.size(); ++row) {
        if (m_jobs.at(row)->id == jobId) {
            emit dataChanged(index(row), index(row));
            return;
        }
    }
}

void JobModel::remove(int jobId)
{
    for (int row = 0; row < m_jobs.size(); ++row) {
        if (m_jobs.at(row)->id == jobId) {
            beginRemoveRows(QModelIndex(), row, row);
            m_jobs.removeAt(row);
            endRemoveRows();
            emit countChanged();
            return;
        }
    }
}

std::shared_ptr<Job> JobModel::find(int jobId) const
{
    for (const auto &job : m_jobs)
        if (job->id == jobId)
            return job;
    return nullptr;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── public api ──────────────────────────────────────────────────────────────────────

FileOperations::FileOperations(QObject *parent)
    : QObject(parent)
{
}

QString FileOperations::uniquePath(const QString &directory, const QString &name)
{
    QString candidate = directory + QLatin1Char('/') + name;
    if (!QFileInfo::exists(candidate) && !QFileInfo(candidate).isSymLink())
        return candidate;
    // "name (2).ext" — the suffix is kept so the copy still opens in the same application.
    const QFileInfo info(name);
    const bool isFolder = QFileInfo(candidate).isDir();
    const QString suffix = isFolder || info.completeSuffix().isEmpty() || name.startsWith(QLatin1Char('.')) ? QString() : QLatin1Char('.') + info.completeSuffix();
    const QString base = suffix.isEmpty() ? name : name.left(name.size() - suffix.size());
    for (int number = 2;; ++number) {
        candidate = QStringLiteral("%1/%2 (%3)%4").arg(directory, base).arg(number).arg(suffix);
        if (!QFileInfo::exists(candidate) && !QFileInfo(candidate).isSymLink())
            return candidate;
    }
}

bool FileOperations::isSameDevice(const QString &first, const QString &second) const
{
    return QStorageInfo(first).device() == QStorageInfo(second).device();
}

int FileOperations::transfer(const QStringList &sources, const QString &destination, int action)
{
    if (sources.isEmpty() || destination.isEmpty())
        return 0;
    const QString verb = action == Qt::MoveAction ? QStringLiteral("move") : action == Qt::LinkAction ? QStringLiteral("link") : QStringLiteral("copy");
    auto job = createJob(verb, QStringLiteral("%1 to %2").arg(countText(int(sources.size())), displayName(destination)));
    job->destination = destination;
    for (const QString &source : sources) {
        const QString cleanSource = QDir::cleanPath(source);
        const QString parent = QFileInfo(cleanSource).absolutePath();
        // A move into the folder it is already in is nothing; a copy there is a duplicate, and gets its own name instead of asking.
        if (verb == QLatin1String("move") && parent == QDir::cleanPath(destination))
            continue;
        const QString target = verb == QLatin1String("copy") && parent == QDir::cleanPath(destination)
            ? uniquePath(destination, QFileInfo(cleanSource).fileName())
            : destination + QLatin1Char('/') + QFileInfo(cleanSource).fileName();
        job->items.append({cleanSource, target});
    }
    if (job->items.isEmpty())
        return 0;
    run(job);
    return job->id;
}

int FileOperations::duplicate(const QStringList &sources)
{
    if (sources.isEmpty())
        return 0;
    auto job = createJob(QStringLiteral("copy"), QStringLiteral("Duplicating %1").arg(countText(int(sources.size()))));
    for (const QString &source : sources) {
        const QFileInfo info(source);
        job->items.append({source, uniquePath(info.absolutePath(), info.fileName())});
    }
    job->destination = QFileInfo(sources.first()).absolutePath();
    run(job);
    return job->id;
}

int FileOperations::trash(const QStringList &paths)
{
    if (paths.isEmpty())
        return 0;
    auto job = createJob(QStringLiteral("trash"), QStringLiteral("%1 to the trash").arg(countText(int(paths.size()))));
    for (const QString &path : paths)
        job->items.append({path, QString()});
    run(job);
    return job->id;
}

int FileOperations::deletePermanently(const QStringList &paths)
{
    if (paths.isEmpty())
        return 0;
    auto job = createJob(QStringLiteral("delete"), QStringLiteral("Deleting %1").arg(countText(int(paths.size()))));
    for (const QString &path : paths)
        job->items.append({path, QString()});
    job->isIndeterminate = true;
    run(job);
    return job->id;
}

int FileOperations::restore(const QStringList &trashPaths)
{
    if (trashPaths.isEmpty())
        return 0;
    auto job = createJob(QStringLiteral("restore"), QStringLiteral("Restoring %1").arg(countText(int(trashPaths.size()))));
    for (const QString &path : trashPaths) {
        QSettings trashInfo(trashRoot() + QStringLiteral("/info/") + QFileInfo(path).fileName() + QStringLiteral(".trashinfo"), QSettings::IniFormat);
        trashInfo.beginGroup(QStringLiteral("Trash Info"));
        const QString original = QUrl::fromPercentEncoding(trashInfo.value(QStringLiteral("Path")).toString().toUtf8());
        if (!original.isEmpty())
            job->items.append({path, original});
    }
    if (job->items.isEmpty())
        return 0;
    run(job);
    return job->id;
}

int FileOperations::emptyTrash()
{
    auto job = createJob(QStringLiteral("empty"), QStringLiteral("Emptying the trash"));
    const QFileInfoList infos = QDir(trashRoot() + QStringLiteral("/files")).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
    for (const QFileInfo &info : infos)
        job->items.append({info.absoluteFilePath(), trashRoot() + QStringLiteral("/info/") + info.fileName() + QStringLiteral(".trashinfo")});
    if (job->items.isEmpty())
        return 0;
    job->isIndeterminate = true;
    run(job);
    return job->id;
}

int FileOperations::extract(const QString &archive)
{
    const QFileInfo info(archive);
    QString base = info.fileName();
    for (const QString &suffix : {QStringLiteral(".tar.gz"), QStringLiteral(".tar.xz"), QStringLiteral(".tar.zst"), QStringLiteral(".tar.bz2")})
        if (base.endsWith(suffix, Qt::CaseInsensitive))
            base.chop(suffix.size());
    if (base == info.fileName())
        base = info.completeBaseName();
    auto job = createJob(QStringLiteral("extract"), QStringLiteral("Extracting %1").arg(info.fileName()));
    job->destination = uniquePath(info.absolutePath(), base);
    job->items.append({archive, job->destination});
    run(job);
    return job->id;
}

int FileOperations::compress(const QStringList &sources)
{
    if (sources.isEmpty())
        return 0;
    const QFileInfo first(sources.first());
    const QString name = sources.size() == 1 ? first.fileName() + QStringLiteral(".zip") : first.absoluteDir().dirName() + QStringLiteral(".zip");
    auto job = createJob(QStringLiteral("compress"), QStringLiteral("Compressing %1").arg(countText(int(sources.size()))));
    job->destination = uniquePath(first.absolutePath(), name);
    for (const QString &source : sources)
        job->items.append({source, job->destination});
    run(job);
    return job->id;
}

QString FileOperations::validateName(const QString &directory, const QString &name, const QString &currentPath) const
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return QStringLiteral("name: cannot be empty");
    if (trimmed.contains(QLatin1Char('/')))
        return QStringLiteral("name: cannot contain /");
    if (trimmed == QLatin1String(".") || trimmed == QLatin1String(".."))
        return QStringLiteral("name: . and .. are reserved");
    const QString target = directory + QLatin1Char('/') + trimmed;
    if (target != currentPath && QFileInfo::exists(target))
        return QStringLiteral("name: %1 already exists here").arg(trimmed);
    return QString();
}

QString FileOperations::rename(const QString &path, const QString &name)
{
    const QFileInfo info(path);
    const QString trimmed = name.trimmed();
    if (trimmed == info.fileName())
        return QString();
    const QString problem = validateName(info.absolutePath(), trimmed, path);
    if (!problem.isEmpty())
        return problem;
    const QString target = info.absolutePath() + QLatin1Char('/') + trimmed;
    if (!QFile::rename(path, target))
        return QStringLiteral("rename: the file system refused");
    pushUndo({QStringLiteral("rename"), QStringLiteral("Renamed to %1").arg(trimmed), {{path, target}}});
    emit jobFinished(0, QStringLiteral("rename"), 1, QStringLiteral("Renamed to %1").arg(trimmed), true, {target}, info.absolutePath());
    return QString();
}

QString FileOperations::createFolder(const QString &parent)
{
    const QString path = uniquePath(parent, QStringLiteral("New folder"));
    if (!QDir().mkdir(path)) {
        emit failed(QStringLiteral("new folder: no permission here"));
        return QString();
    }
    pushUndo({QStringLiteral("create"), QStringLiteral("Created %1").arg(QFileInfo(path).fileName()), {{path, path}}});
    return path;
}

QString FileOperations::createFile(const QString &parent)
{
    const QString path = uniquePath(parent, QStringLiteral("New file.txt"));
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        emit failed(QStringLiteral("new file: no permission here"));
        return QString();
    }
    file.close();
    pushUndo({QStringLiteral("create"), QStringLiteral("Created %1").arg(QFileInfo(path).fileName()), {{path, path}}});
    return path;
}

void FileOperations::cancel(int jobId)
{
    if (auto job = m_jobs.find(jobId)) {
        job->isCancelled = true;
        QMutexLocker locker(&job->mutex);
        job->conflictAnswer = QStringLiteral("skip");
        job->answered.wakeAll();
    }
}

void FileOperations::resolveConflict(int jobId, const QString &answer, bool isForAll)
{
    auto job = m_jobs.find(jobId);
    if (!job)
        return;
    QMutexLocker locker(&job->mutex);
    job->conflictAnswer = answer;
    if (isForAll)
        job->conflictPolicy = answer;
    job->state = QStringLiteral("running");
    job->conflictName.clear();
    job->answered.wakeAll();
    locker.unlock();
    m_jobs.update(jobId);
}

void FileOperations::undo()
{
    if (m_undoStack.isEmpty())
        return;
    const UndoRecord record = m_undoStack.takeLast();
    emit undoChanged();
    if (record.kind == QLatin1String("rename")) {
        const auto &[original, renamed] = record.pairs.first();
        if (QFile::rename(renamed, original))
            emit jobFinished(0, QStringLiteral("undo"), 1, QStringLiteral("Name restored"), false, {original}, QFileInfo(original).absolutePath());
        return;
    }
    if (record.kind == QLatin1String("copy") || record.kind == QLatin1String("create") || record.kind == QLatin1String("restore")) {
        QStringList results;
        for (const auto &[original, result] : record.pairs)
            results.append(result);
        auto job = createJob(QStringLiteral("trash"), QStringLiteral("Undoing"));
        job->isUndo = true;
        for (const QString &result : results)
            job->items.append({result, QString()});
        run(job);
        return;
    }
    // A move and a trash are both undone by putting each thing back exactly where it stood.
    auto job = createJob(record.kind == QLatin1String("trash") ? QStringLiteral("restore") : QStringLiteral("move"), QStringLiteral("Undoing"));
    job->isUndo = true;
    for (const auto &[original, result] : record.pairs)
        job->items.append({result, original});
    job->destination = record.pairs.isEmpty() ? QString() : QFileInfo(record.pairs.first().first).absolutePath();
    run(job);
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── running ─────────────────────────────────────────────────────────────────────────

std::shared_ptr<Job> FileOperations::createJob(const QString &verb, const QString &title)
{
    auto job = std::make_shared<Job>();
    job->id = m_nextJobId++;
    job->verb = verb;
    job->title = title;
    return job;
}

void FileOperations::run(const std::shared_ptr<Job> &job)
{
    m_jobs.add(job);
    QPointer<FileOperations> guard(this);
    auto future = QtConcurrent::run([this, job] { execute(job); });
    future.then(this, [guard, job] {
        if (guard)
            guard->finish(job);
    });
}

void FileOperations::report(const std::shared_ptr<Job> &job)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - job->lastReportAt.load() < REPORT_INTERVAL_MS)
        return;
    job->lastReportAt = now;
    QPointer<FileOperations> guard(this);
    const int jobId = job->id;
    QMetaObject::invokeMethod(this, [guard, jobId] {
        if (guard)
            guard->m_jobs.update(jobId);
    }, Qt::QueuedConnection);
}

void FileOperations::execute(const std::shared_ptr<Job> &job)
{
    const QString &verb = job->verb;
    auto setDetail = [&](const QString &detail) {
        QMutexLocker locker(&job->mutex);
        job->detail = detail;
    };

    if (verb == QLatin1String("copy") || verb == QLatin1String("move")) {
        qint64 total = 0;
        for (const auto &[source, target] : job->items)
            total += measure(source);
        job->totalBytes = total;
        for (const auto &[source, target] : job->items) {
            if (job->isCancelled)
                break;
            setDetail(QFileInfo(source).fileName());
            report(job);
            if (transferItem(job, source, target, verb == QLatin1String("move")))
                job->doneCount++;
        }
        return;
    }
    if (verb == QLatin1String("link")) {
        for (const auto &[source, target] : job->items) {
            const QString linkPath = uniquePath(QFileInfo(target).absolutePath(), QFileInfo(target).fileName());
            if (QFile::link(source, linkPath)) {
                QMutexLocker locker(&job->mutex);
                job->results.append(linkPath);
                job->doneCount++;
            }
        }
        return;
    }
    if (verb == QLatin1String("trash")) {
        for (auto &[source, target] : job->items) {
            if (job->isCancelled)
                break;
            setDetail(QFileInfo(source).fileName());
            QString pathInTrash;
            if (QFile::moveToTrash(source, &pathInTrash)) {
                target = pathInTrash;
                QMutexLocker locker(&job->mutex);
                job->results.append(pathInTrash);
                job->doneCount++;
            } else {
                QMutexLocker locker(&job->mutex);
                job->error = QStringLiteral("trash: %1 could not be moved").arg(QFileInfo(source).fileName());
            }
            report(job);
        }
        return;
    }
    if (verb == QLatin1String("delete") || verb == QLatin1String("empty")) {
        for (const auto &[source, sidecar] : job->items) {
            if (job->isCancelled)
                break;
            setDetail(QFileInfo(source).fileName());
            if (removePath(source)) {
                if (!sidecar.isEmpty())
                    QFile::remove(sidecar);
                job->doneCount++;
            }
            report(job);
        }
        return;
    }
    if (verb == QLatin1String("restore")) {
        for (auto &[source, target] : job->items) {
            if (job->isCancelled)
                break;
            setDetail(QFileInfo(target).fileName());
            QDir().mkpath(QFileInfo(target).absolutePath());
            const QString destination = QFileInfo::exists(target) ? uniquePath(QFileInfo(target).absolutePath(), QFileInfo(target).fileName()) : target;
            if (transferItem(job, source, destination, true)) {
                QFile::remove(trashRoot() + QStringLiteral("/info/") + QFileInfo(source).fileName() + QStringLiteral(".trashinfo"));
                target = destination;
                job->doneCount++;
            }
        }
        return;
    }
    if (verb == QLatin1String("extract")) {
        const auto &[archive, destination] = job->items.first();
        setDetail(QFileInfo(archive).fileName());
        QDir().mkpath(destination);
        // Progress is real: the listing gives every entry's size, -v names each entry as it starts, and the file growing on disk fills in the one in flight.
        QHash<QString, qint64> sizes;
        {
            QProcess listing;
            listing.start(QStringLiteral("bsdtar"), {QStringLiteral("-tvf"), archive});
            listing.waitForFinished(-1);
            static const QRegularExpression entry(QStringLiteral(R"(^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s(.*)$)"));
            qint64 total = 0;
            for (const QString &line : QString::fromUtf8(listing.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const auto match = entry.match(line);
                if (!match.hasMatch())
                    continue;
                const qint64 size = match.captured(1).toLongLong();
                sizes.insert(match.captured(2), size);
                total += size;
            }
            job->totalBytes = total;
        }
        qint64 finishedBytes = 0;
        QString current;
        const auto onLine = [&](const QString &line, bool isComplete) {
            if (!line.startsWith(QLatin1String("x ")))
                return;
            if (isComplete) {
                finishedBytes += sizes.value(line.mid(2));
                current.clear();
            } else {
                current = line.mid(2);
            }
            job->doneBytes = finishedBytes;
            report(job);
        };
        const auto onTick = [&] {
            if (current.isEmpty())
                return;
            job->doneBytes = finishedBytes + std::min(sizes.value(current), QFileInfo(destination + QLatin1Char('/') + current).size());
            report(job);
        };
        if (runProcess(job, QStringLiteral("bsdtar"), {QStringLiteral("-xvf"), archive, QStringLiteral("-C"), destination}, QString(), onLine, onTick)) {
            QMutexLocker locker(&job->mutex);
            job->results.append(destination);
            job->doneCount++;
        } else {
            QDir(destination).removeRecursively();
        }
        return;
    }
    if (verb == QLatin1String("compress")) {
        QStringList arguments = {QStringLiteral("-a"), QStringLiteral("-cvf"), job->destination};
        for (const auto &[source, target] : job->items)
            arguments.append(QFileInfo(source).fileName());
        setDetail(QFileInfo(job->destination).fileName());
        // Every file's size up front, by the relative name bsdtar will print for it. The archive is compressed, so its growth only fills in the entry in flight, capped at that entry's size.
        const QString base = QFileInfo(job->items.first().first).absolutePath();
        QHash<QString, qint64> sizes;
        qint64 total = 0;
        for (const auto &[source, target] : job->items) {
            const QFileInfo info(source);
            if (info.isFile()) {
                sizes.insert(info.fileName(), info.size());
                total += info.size();
                continue;
            }
            QDirIterator walker(source, QDir::Files | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
            while (walker.hasNext()) {
                const QFileInfo file = walker.nextFileInfo();
                if (file.isSymLink())
                    continue;
                sizes.insert(QDir(base).relativeFilePath(file.filePath()), file.size());
                total += file.size();
            }
        }
        job->totalBytes = total;
        qint64 finishedBytes = 0;
        qint64 archiveAtStart = 0;
        QString current;
        const auto onLine = [&](const QString &line, bool isComplete) {
            if (!line.startsWith(QLatin1String("a ")))
                return;
            if (isComplete) {
                finishedBytes += sizes.value(line.mid(2));
                current.clear();
            } else if (current != line.mid(2)) {
                current = line.mid(2);
                archiveAtStart = QFileInfo(job->destination).size();
            }
            job->doneBytes = finishedBytes;
            report(job);
        };
        const auto onTick = [&] {
            if (current.isEmpty())
                return;
            const qint64 grown = QFileInfo(job->destination).size() - archiveAtStart;
            job->doneBytes = finishedBytes + std::clamp(grown, qint64(0), sizes.value(current));
            report(job);
        };
        if (runProcess(job, QStringLiteral("bsdtar"), arguments, base, onLine, onTick)) {
            QMutexLocker locker(&job->mutex);
            job->results.append(job->destination);
            job->doneCount = int(job->items.size());
        } else {
            QFile::remove(job->destination);
        }
    }
}

void FileOperations::finish(const std::shared_ptr<Job> &job)
{
    const int count = job->doneCount.load();
    {
        QMutexLocker locker(&job->mutex);
        job->state = job->isCancelled ? QStringLiteral("cancelled") : job->error.isEmpty() ? QStringLiteral("done") : QStringLiteral("failed");
    }
    m_jobs.update(job->id);
    const int jobId = job->id;
    QTimer::singleShot(FINISHED_ROW_LINGER_MS, this, [this, jobId] { m_jobs.remove(jobId); });

    if (!job->error.isEmpty())
        emit failed(job->error);
    if (count == 0)
        return;

    const QString &verb = job->verb;
    QList<std::pair<QString, QString>> pairs;
    QStringList resultPaths;
    if (verb == QLatin1String("copy") || verb == QLatin1String("move") || verb == QLatin1String("restore") || verb == QLatin1String("trash")) {
        for (const auto &[source, target] : job->items) {
            if (target.isEmpty() || !QFileInfo::exists(target) || (verb != QLatin1String("trash") && QFileInfo::exists(source) && verb != QLatin1String("copy")))
                continue;
            pairs.append({source, target});
            resultPaths.append(target);
        }
    } else {
        resultPaths = job->results;
        for (const QString &result : job->results)
            pairs.append({result, result});
    }

    const QString destinationName = displayName(job->destination);
    QString summary;
    if (verb == QLatin1String("copy"))
        summary = QStringLiteral("Copied %1 to %2").arg(countText(count), destinationName);
    else if (verb == QLatin1String("move"))
        summary = job->isUndo ? QStringLiteral("Put back %1").arg(countText(count)) : QStringLiteral("Moved %1 to %2").arg(countText(count), destinationName);
    else if (verb == QLatin1String("link"))
        summary = QStringLiteral("Linked %1 in %2").arg(countText(count), destinationName);
    else if (verb == QLatin1String("trash"))
        summary = job->isUndo ? QStringLiteral("Undone") : QStringLiteral("Moved %1 to the trash").arg(countText(count));
    else if (verb == QLatin1String("delete"))
        summary = QStringLiteral("Deleted %1 for good").arg(countText(count));
    else if (verb == QLatin1String("empty"))
        summary = QStringLiteral("Trash emptied");
    else if (verb == QLatin1String("restore"))
        summary = QStringLiteral("Restored %1").arg(countText(count));
    else if (verb == QLatin1String("extract"))
        summary = QStringLiteral("Extracted to %1").arg(QFileInfo(job->destination).fileName());
    else if (verb == QLatin1String("compress"))
        summary = QStringLiteral("Compressed to %1").arg(QFileInfo(job->destination).fileName());

    const bool isUndoable = !job->isUndo && !pairs.isEmpty() && verb != QLatin1String("delete") && verb != QLatin1String("empty");
    if (isUndoable) {
        const QString kind = verb == QLatin1String("link") || verb == QLatin1String("extract") || verb == QLatin1String("compress") ? QStringLiteral("copy") : verb;
        pushUndo({kind, summary, pairs});
    }
    emit jobFinished(job->id, verb, count, summary, isUndoable, resultPaths, job->destination);
}

void FileOperations::pushUndo(UndoRecord record)
{
    m_undoStack.append(std::move(record));
    // A stack that only grows is a memory of every session; thirty steps back is further than anyone walks.
    if (m_undoStack.size() > 30)
        m_undoStack.removeFirst();
    emit undoChanged();
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
// #region ── transfer mechanics ──────────────────────────────────────────────────────────────

QString FileOperations::askConflict(const std::shared_ptr<Job> &job, const QString &target)
{
    QMutexLocker locker(&job->mutex);
    if (!job->conflictPolicy.isEmpty())
        return job->conflictPolicy;
    job->state = QStringLiteral("conflict");
    job->conflictName = QFileInfo(target).fileName();
    job->conflictAnswer.clear();
    const int jobId = job->id;
    const QString name = job->conflictName;
    const QString destination = displayName(QFileInfo(target).absolutePath());
    QPointer<FileOperations> guard(this);
    QMetaObject::invokeMethod(this, [guard, jobId, name, destination] {
        if (!guard)
            return;
        guard->m_jobs.update(jobId);
        emit guard->conflict(jobId, name, destination);
    }, Qt::QueuedConnection);
    while (job->conflictAnswer.isEmpty() && !job->isCancelled)
        job->answered.wait(&job->mutex);
    return job->isCancelled ? QStringLiteral("skip") : job->conflictAnswer;
}

bool FileOperations::transferItem(const std::shared_ptr<Job> &job, const QString &source, QString target, bool isMove)
{
    const QFileInfo sourceInfo(source);
    if (!sourceInfo.exists() && !sourceInfo.isSymLink())
        return false;
    if (sourceInfo.isDir() && (target == source || target.startsWith(source + QLatin1Char('/')))) {
        QMutexLocker locker(&job->mutex);
        job->error = QStringLiteral("%1: a folder cannot go inside itself").arg(sourceInfo.fileName());
        return false;
    }
    if (QFileInfo::exists(target) && target != source) {
        const QString answer = askConflict(job, target);
        if (answer == QLatin1String("skip")) {
            job->doneBytes += measure(source);
            return false;
        }
        if (answer == QLatin1String("keep"))
            target = uniquePath(QFileInfo(target).absolutePath(), QFileInfo(target).fileName());
        else if (!removePath(target))
            return false;
    }
    // Updated in place so the undo record and the selection after the drop point at the name the item actually landed under.
    for (auto &item : job->items)
        if (item.first == source)
            item.second = target;

    if (isMove && QFile::rename(source, target)) {
        job->doneBytes += sourceInfo.isDir() ? measure(target) : sourceInfo.size();
        report(job);
        return true;
    }
    if (!copyRecursive(job, source, target)) {
        if (!job->isCancelled) {
            QMutexLocker locker(&job->mutex);
            if (job->error.isEmpty())
                job->error = QStringLiteral("%1: could not be written to %2").arg(sourceInfo.fileName(), displayName(QFileInfo(target).absolutePath()));
        }
        removePath(target);
        return false;
    }
    if (isMove)
        removePath(source);
    return true;
}

bool FileOperations::copyRecursive(const std::shared_ptr<Job> &job, const QString &source, const QString &target)
{
    if (job->isCancelled)
        return false;
    const QFileInfo info(source);
    if (info.isSymLink())
        return QFile::link(info.symLinkTarget(), target);
    if (info.isDir()) {
        if (!QDir().mkpath(target))
            return false;
        const QFileInfoList children = QDir(source).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QFileInfo &child : children)
            if (!copyRecursive(job, child.absoluteFilePath(), target + QLatin1Char('/') + child.fileName()))
                return false;
        QFile::setPermissions(target, info.permissions());
        return true;
    }
    return copyFile(job, source, target);
}

bool FileOperations::copyFile(const std::shared_ptr<Job> &job, const QString &source, const QString &target)
{
    QFile input(source);
    QFile output(target);
    if (!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly))
        return false;
    QByteArray buffer;
    while (!input.atEnd()) {
        if (job->isCancelled)
            return false;
        buffer = input.read(CHUNK_BYTES);
        if (buffer.isEmpty() && input.error() != QFileDevice::NoError)
            return false;
        if (output.write(buffer) != buffer.size())
            return false;
        job->doneBytes += buffer.size();
        report(job);
    }
    output.setPermissions(input.permissions());
    output.setFileTime(QFileInfo(source).lastModified(), QFileDevice::FileModificationTime);
    return true;
}

bool FileOperations::runProcess(const std::shared_ptr<Job> &job, const QString &program, const QStringList &arguments, const QString &workingDirectory,
                                const std::function<void(const QString &, bool)> &onLine, const std::function<void()> &onTick)
{
    QProcess process;
    if (!workingDirectory.isEmpty())
        process.setWorkingDirectory(workingDirectory);
    process.start(program, arguments);
    if (!process.waitForStarted(3000)) {
        QMutexLocker locker(&job->mutex);
        job->error = QStringLiteral("%1: not installed").arg(program);
        return false;
    }
    QString firstError;
    QByteArray pending;
    const auto drain = [&] {
        pending += process.readAllStandardError();
        qsizetype newline;
        while ((newline = pending.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(pending.left(newline)).trimmed();
            pending.remove(0, newline + 1);
            // bsdtar's own complaints start with its name; everything else is a verbose entry line.
            if (line.startsWith(program + QLatin1Char(':'))) {
                if (firstError.isEmpty())
                    firstError = line.mid(program.size() + 1).trimmed();
            } else if (onLine) {
                onLine(line, true);
            }
        }
        if (onLine && !pending.isEmpty())
            onLine(QString::fromUtf8(pending).trimmed(), false);
    };
    while (!process.waitForFinished(100)) {
        if (job->isCancelled) {
            process.kill();
            process.waitForFinished(1000);
            return false;
        }
        drain();
        if (onTick)
            onTick();
    }
    drain();
    const QString rest = QString::fromUtf8(pending).trimmed();
    if (firstError.isEmpty() && rest.startsWith(program + QLatin1Char(':')))
        firstError = rest.mid(program.size() + 1).trimmed();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        QMutexLocker locker(&job->mutex);
        job->error = QStringLiteral("%1: %2").arg(program, firstError.isEmpty() ? rest.section(QLatin1Char('\n'), 0, 0) : firstError);
        return false;
    }
    return true;
}

// #endregion ─────────────────────────────────────────────────────────────────────────────────
