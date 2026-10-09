#pragma once

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QRegularExpression>
#include <QSet>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>

#include "fileEntry.h"

// The contents of one folder pane. Loading is split from showing: `load` reads off the GUI thread while the outgoing view is still leaving, and `commit` swaps the rows in once the leave has finished, so the read hides behind the animation instead of after it.
class FolderModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QString pendingPath READ pendingPath NOTIFY pendingPathChanged)
    Q_PROPERTY(QString mode READ mode NOTIFY pathChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(bool isSearching READ isSearching NOTIFY isSearchingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int folderCount READ folderCount NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY countChanged)
    Q_PROPERTY(qint64 totalSize READ totalSize NOTIFY countChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectionChanged)
    Q_PROPERTY(qint64 selectedSize READ selectedSize NOTIFY selectionChanged)
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(QString sortKey READ sortKey WRITE setSortKey NOTIFY sortChanged)
    Q_PROPERTY(bool sortDescending READ sortDescending WRITE setSortDescending NOTIFY sortChanged)
    Q_PROPERTY(bool foldersFirst READ foldersFirst WRITE setFoldersFirst NOTIFY sortChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QStringList cutPaths READ cutPaths WRITE setCutPaths NOTIFY cutPathsChanged)
    // A file picker's filter: files must match one of these globs; folders always pass so the picker can still walk.
    Q_PROPERTY(QStringList nameFilters READ nameFilters WRITE setNameFilters NOTIFY nameFiltersChanged)
    Q_PROPERTY(bool isFoldersOnly READ isFoldersOnly WRITE setFoldersOnly NOTIFY nameFiltersChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        PathRole,
        UrlRole,
        IsDirectoryRole,
        IsHiddenRole,
        IsSymlinkRole,
        SizeRole,
        SizeTextRole,
        ModifiedRole,
        ModifiedTextRole,
        MimeTypeRole,
        KindRole,
        SuffixRole,
        ChildCountRole,
        IsSelectedRole,
        IsCutRole,
        OriginalPathRole,
        DeletedAtTextRole,
        CanThumbnailRole,
    };
    Q_ENUM(Role)

    explicit FolderModel(QObject *parent = nullptr);
    ~FolderModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString path() const { return m_path; }
    QString pendingPath() const { return m_pendingPath; }
    QString mode() const { return m_mode; }
    bool isLoading() const { return m_isLoading; }
    bool isSearching() const { return m_isSearching; }
    QString error() const { return m_error; }
    int folderCount() const;
    int totalCount() const { return int(m_all.size()); }
    qint64 totalSize() const;
    int selectedCount() const { return int(m_selected.size()); }
    qint64 selectedSize() const;
    int currentIndex() const { return m_currentIndex; }
    void setCurrentIndex(int index);
    QString sortKey() const { return m_sortKey; }
    void setSortKey(const QString &key);
    bool sortDescending() const { return m_sortDescending; }
    void setSortDescending(bool isDescending);
    bool foldersFirst() const { return m_foldersFirst; }
    void setFoldersFirst(bool isFirst);
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool isShown);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    QStringList cutPaths() const { return m_cutPaths; }
    void setCutPaths(const QStringList &paths);
    QStringList nameFilters() const { return m_nameFilters; }
    void setNameFilters(const QStringList &filters);
    bool isFoldersOnly() const { return m_isFoldersOnly; }
    void setFoldersOnly(bool isFoldersOnly);

    Q_INVOKABLE void load(const QString &path);
    Q_INVOKABLE void commit();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void cancelSearch();

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int indexOfPath(const QString &path) const;
    Q_INVOKABLE int indexOfPrefix(const QString &prefix, int from) const;

    Q_INVOKABLE void select(int row);
    Q_INVOKABLE void toggle(int row);
    Q_INVOKABLE void selectRange(int from, int to, bool isAdditive);
    // The rubber band: the rows under it, on top of whatever was selected when it started.
    Q_INVOKABLE void selectRows(const QVariantList &rows, const QStringList &basePaths);
    Q_INVOKABLE void selectPaths(const QStringList &paths);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE bool isSelected(int row) const;
    Q_INVOKABLE QStringList selectedPaths() const;

signals:
    void pathChanged();
    void pendingPathChanged();
    void isLoadingChanged();
    void isSearchingChanged();
    void errorChanged();
    void countChanged();
    void selectionChanged();
    void currentIndexChanged();
    void sortChanged();
    void showHiddenChanged();
    void filterChanged();
    void cutPathsChanged();
    void nameFiltersChanged();
    // The read of `path` has finished and `commit` may swap it in.
    void loaded(const QString &path);
    // A path that vanished from under the pane (deleted, unmounted); the pane walks up to the nearest folder that still exists.
    void pathLost(const QString &path);

private:
    void startRead(const QString &path, bool isRefresh);
    void finishRead(int generation, const QString &path, QList<FileEntry> entries, const QString &error, bool isRefresh);
    void applyDiff(const QList<FileEntry> &next);
    QList<FileEntry> visibleSorted(const QList<FileEntry> &source) const;
    bool passesFilter(const FileEntry &entry) const;
    bool lessThan(const FileEntry &left, const FileEntry &right) const;
    void resort();
    void rewatch();
    void setLoading(bool isLoading);
    void emitSelectionRoles();

    QList<FileEntry> m_all;
    QList<FileEntry> m_rows;
    QList<FileEntry> m_pending;
    QSet<QString> m_selected;
    QStringList m_cutPaths;
    QStringList m_nameFilters;
    QList<QRegularExpression> m_namePatterns;
    QString m_path;
    QString m_pendingPath;
    QString m_pendingError;
    QString m_mode = QStringLiteral("folder");
    QString m_error;
    QString m_sortKey = QStringLiteral("name");
    QString m_filter;
    QString m_searchQuery;
    QFileSystemWatcher m_watcher;
    QTimer m_refreshDebounce;
    int m_generation = 0;
    int m_currentIndex = -1;
    bool m_sortDescending = false;
    bool m_foldersFirst = true;
    bool m_showHidden = false;
    bool m_isFoldersOnly = false;
    bool m_isLoading = false;
    bool m_isSearching = false;
    bool m_hasPending = false;
    std::shared_ptr<std::atomic_bool> m_searchCancel;
};
