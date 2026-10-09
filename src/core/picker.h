#pragma once

#include <QJsonObject>
#include <QObject>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

// The window as a file picker. Started by the portal backend with `--pick <request>`; the answer leaves on stdout as one file URI per line, and quitting without one is a cancel. Inactive in an ordinary run.
class Picker : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool isActive READ isActive CONSTANT)
    // "open" picks files, "folder" picks a folder, "save" names a new file in a folder.
    Q_PROPERTY(QString mode READ mode CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString acceptLabel READ acceptLabel CONSTANT)
    Q_PROPERTY(bool isMultiple READ isMultiple CONSTANT)
    Q_PROPERTY(QString suggestedName READ suggestedName CONSTANT)
    // [{ name, patterns: [glob, …] }, …]; empty when the asking app named none.
    Q_PROPERTY(QVariantList filters READ filters CONSTANT)
    Q_PROPERTY(int initialFilter READ initialFilter CONSTANT)

public:
    explicit Picker(QObject *parent = nullptr);

    // Reads the request handed over on the command line; returns the folder to open at, or an empty string.
    static QString configure(const QByteArray &request);

    bool isActive() const;
    QString mode() const;
    QString title() const;
    QString acceptLabel() const;
    bool isMultiple() const;
    QString suggestedName() const;
    QVariantList filters() const;
    int initialFilter() const;

    Q_INVOKABLE void accept(const QStringList &paths, int filterIndex);
    Q_INVOKABLE void cancel();
};
