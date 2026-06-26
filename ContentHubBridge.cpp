#include "ContentHubBridge.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QRegExp>
#include <QStandardPaths>

ContentHubBridge::ContentHubBridge(QObject *parent)
    : QObject(parent)
{
}

QString ContentHubBridge::readTextFile(const QUrl &url) const
{
    if (!url.isLocalFile()) {
        return QString();
    }

    QFile file(url.toLocalFile());
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    return QString::fromUtf8(file.readAll());
}

QUrl ContentHubBridge::writeSharedTextFile(const QString &title, const QString &content) const
{
    if (content.isEmpty()) {
        return QUrl();
    }

    const QString basePath = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (basePath.isEmpty()) {
        return QUrl();
    }

    QDir dir(basePath);
    if (!dir.mkpath(QStringLiteral("ContentHubOutgoing"))) {
        return QUrl();
    }
    if (!dir.cd(QStringLiteral("ContentHubOutgoing"))) {
        return QUrl();
    }

    QString safeTitle = title.trimmed();
    if (safeTitle.isEmpty()) {
        safeTitle = QStringLiteral("shared-task");
    }
    safeTitle.replace(QRegExp(QStringLiteral("[^A-Za-z0-9._-]+")), QStringLiteral("-"));
    safeTitle = safeTitle.left(48).trimmed();
    if (safeTitle.isEmpty()) {
        safeTitle = QStringLiteral("shared-task");
    }

    const QByteArray digest = QCryptographicHash::hash(
                (content + QString::number(QDateTime::currentMSecsSinceEpoch())).toUtf8(),
                QCryptographicHash::Sha1).toHex().left(10);
    const QString filePath = dir.filePath(QStringLiteral("%1-%2.txt").arg(safeTitle, QString::fromLatin1(digest)));

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        return QUrl();
    }

    file.write(content.toUtf8());
    file.close();

    return QUrl::fromLocalFile(filePath);
}
