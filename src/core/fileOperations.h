#pragma once

#include <QAbstractListModel>
#include <QMutex>
#include <QWaitCondition>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <functional>
#include <memory>

// #region ── jobs ────────────────────────────────────────────────────────────────────────────

struct Job {
    int id = 0;
    QString verb;
    QString destination;
    QList<std::pair<QString, QString>> items;
    QStringList results;
    QString title;
    QString detail;
    QString state = QStringLiteral("running");
    QString error;
    QString conflictName;
    QString conflictPolicy;
    QString conflictAnswer;
    std::atomic<qint64> totalBytes = 0;
    std::atomic<qint64> doneBytes = 0;
    std::atomic<qint64> lastReportAt = 0;
    std::atomic_int doneCount = 0;
    bool isIndeterminate = false;
    bool isUndo = false;
    std::atomic_bool isCancelled = false;
    QMutex mutex;
    QWaitCondition answered;
};

// The transfers the interface is showing; a row stays for a beat after it finishes so its bar can be seen reaching the end.
class JobModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("owned by FileOperations")
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role { JobIdRole = Qt::UserRole + 1, VerbRole, TitleRole, DetailRole, ProgressRole, StateRole, ConflictNameRole, ErrorRole };

    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void add(const std::shared_ptr<Job> &job);
    void update(int jobId);
    void remove(int jobId);
    std::shared_ptr<Job> find(int jobId) const;

signals:
    void countChanged();

private:
    QList<std::shared_ptr<Job>> m_jobs;
};

// #endregion ─────────────────────────────────────────────────────────────────────────────────

class FileOperations : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(JobModel *jobs READ jobs CONSTANT)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)
    Q_PROPERTY(QString undoText READ undoText NOTIFY undoChanged)

public:
    explicit FileOperations(QObject *parent = nullptr);

    JobModel *jobs() { return &m_jobs; }
    bool canUndo() const { return !m_undoStack.isEmpty(); }
    QString undoText() const { return m_undoStack.isEmpty() ? QString() : m_undoStack.last().text; }

    // `action` is a Qt.DropAction: 1 copy, 2 move, 4 link.
    Q_INVOKABLE int transfer(const QStringList &sources, const QString &destination, int action);
    Q_INVOKABLE int copy(const QStringList &sources, const QString &destination) { return transfer(sources, destination, Qt::CopyAction); }
    Q_INVOKABLE int move(const QStringList &sources, const QString &destination) { return transfer(sources, destination, Qt::MoveAction); }
    Q_INVOKABLE int duplicate(const QStringList &sources);
    Q_INVOKABLE int trash(const QStringList &paths);
    Q_INVOKABLE int deletePermanently(const QStringList &paths);
    Q_INVOKABLE int restore(const QStringList &trashPaths);
    Q_INVOKABLE int emptyTrash();
    Q_INVOKABLE int extract(const QString &archive);
    Q_INVOKABLE int compress(const QStringList &sources);
    Q_INVOKABLE QString rename(const QString &path, const QString &name);
    Q_INVOKABLE QString createFolder(const QString &parent);
    Q_INVOKABLE QString createFile(const QString &parent);
    Q_INVOKABLE void cancel(int jobId);
    Q_INVOKABLE void resolveConflict(int jobId, const QString &answer, bool isForAll);
    Q_INVOKABLE void undo();
    Q_INVOKABLE bool isSameDevice(const QString &first, const QString &second) const;
    Q_INVOKABLE QString validateName(const QString &directory, const QString &name, const QString &currentPath) const;
    Q_INVOKABLE static QString uniquePath(const QString &directory, const QString &name);

signals:
    void undoChanged();
    // `undoable` says whether the pill can offer the reversal; `paths` are where the results now are, so the pane can select them.
    void jobFinished(int jobId, const QString &verb, int count, const QString &summary, bool isUndoable, const QStringList &paths, const QString &destination);
    void conflict(int jobId, const QString &name, const QString &destination);
    void failed(const QString &message);

private:
    struct UndoRecord {
        QString kind;
        QString text;
        QList<std::pair<QString, QString>> pairs;
    };

    std::shared_ptr<Job> createJob(const QString &verb, const QString &title);
    void run(const std::shared_ptr<Job> &job);
    void execute(const std::shared_ptr<Job> &job);
    void finish(const std::shared_ptr<Job> &job);
    void pushUndo(UndoRecord record);
    void report(const std::shared_ptr<Job> &job);

    bool transferItem(const std::shared_ptr<Job> &job, const QString &source, QString target, bool isMove);
    bool copyRecursive(const std::shared_ptr<Job> &job, const QString &source, const QString &target);
    bool copyFile(const std::shared_ptr<Job> &job, const QString &source, const QString &target);
    QString askConflict(const std::shared_ptr<Job> &job, const QString &target);
    // onLine gets what the tool writes to stderr, line by line; isComplete is false for the unfinished last line. bsdtar -v writes an entry's name
    // when it starts on it and the newline only when it is done, so an unfinished line is the entry in flight. onTick runs every poll.
    bool runProcess(const std::shared_ptr<Job> &job, const QString &program, const QStringList &arguments, const QString &workingDirectory,
                    const std::function<void(const QString &, bool)> &onLine = {}, const std::function<void()> &onTick = {});

    JobModel m_jobs;
    QList<UndoRecord> m_undoStack;
    int m_nextJobId = 1;
};
