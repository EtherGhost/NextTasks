#ifndef CONTENTHUBBRIDGE_H
#define CONTENTHUBBRIDGE_H

#include <QObject>
#include <QString>
#include <QUrl>

class ContentHubBridge : public QObject
{
    Q_OBJECT

public:
    explicit ContentHubBridge(QObject *parent = nullptr);

    Q_INVOKABLE QString readTextFile(const QUrl &url) const;
    Q_INVOKABLE QUrl writeSharedTextFile(const QString &title, const QString &content) const;
};

#endif
