#include "CalDavNetwork.h"

#include <QByteArray>
#include <QDateTime>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>

namespace {
QString normalizedServerUrl(QString value)
{
    value = value.trimmed();
    while (value.endsWith(QLatin1Char('/'))) {
        value.chop(1);
    }
    return value;
}

QString escapeXml(QString value)
{
    return value
        .replace(QLatin1Char('&'), QStringLiteral("&amp;"))
        .replace(QLatin1Char('<'), QStringLiteral("&lt;"))
        .replace(QLatin1Char('>'), QStringLiteral("&gt;"))
        .replace(QLatin1Char('"'), QStringLiteral("&quot;"))
        .replace(QLatin1Char('\''), QStringLiteral("&apos;"));
}

QString calendarSlug(const QString &value)
{
    QString slug = value.trimmed().toLower();
    slug.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    slug.replace(QRegularExpression(QStringLiteral("^-+|-+$")), QString());
    if (slug.isEmpty()) {
        slug = QStringLiteral("tasks");
    }
    return slug + QStringLiteral("-") + QString::number(QDateTime::currentMSecsSinceEpoch());
}

QString colorValue(QString value)
{
    value = value.trimmed();
    if (value.isEmpty()) {
        return QString();
    }
    if (!value.startsWith(QLatin1Char('#'))) {
        value.prepend(QLatin1Char('#'));
    }
    if (QRegularExpression(QStringLiteral("^#[0-9A-Fa-f]{6}$")).match(value).hasMatch()) {
        return value.toUpper();
    }
    return QString();
}
}

CalDavNetwork::CalDavNetwork(QObject *parent)
    : QObject(parent)
{
}

void CalDavNetwork::createCalendar(int generation,
                                   const QString &serverUrl,
                                   const QString &userName,
                                   const QString &secret,
                                   const QString &title)
{
    const QString base = normalizedServerUrl(serverUrl);
    const QString displayName = title.trimmed();
    if (base.isEmpty() || userName.isEmpty() || secret.isEmpty() || displayName.isEmpty()) {
        emit calendarCreateFailed(tr("Task list name is required."), generation);
        return;
    }

    QNetworkRequest request = authorizedRequest(base, userName, secret, QStringLiteral("/remote.php/dav/calendars/%1/%2/")
        .arg(QString::fromUtf8(QUrl::toPercentEncoding(userName)),
             QString::fromUtf8(QUrl::toPercentEncoding(calendarSlug(displayName)))));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/xml; charset=utf-8"));

    const QByteArray body = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<d:mkcol xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\">"
        "<d:set><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"
        "<d:displayname>%1</d:displayname>"
        "<c:supported-calendar-component-set><c:comp name=\"VTODO\"/></c:supported-calendar-component-set>"
        "</d:prop></d:set></d:mkcol>")
        .arg(escapeXml(displayName))
        .toUtf8();

    QNetworkReply *reply = manager.sendCustomRequest(request, QByteArrayLiteral("MKCOL"), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if (status >= 200 && status < 300) {
            emit calendarCreated(generation);
            return;
        }
        if (status == 405 || status == 409 || status == 412) {
            emit calendarCreateFailed(tr("A task list with that name may already exist."), generation);
            return;
        }
        if (status > 0) {
            emit calendarCreateFailed(tr("Task list creation failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit calendarCreateFailed(tr("Task list creation failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::updateCalendar(int generation,
                                   const QString &serverUrl,
                                   const QString &userName,
                                   const QString &secret,
                                   const QString &calendarHref,
                                   const QString &title,
                                   const QString &color)
{
    const QString displayName = title.trimmed();
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || calendarHref.trimmed().isEmpty() || displayName.isEmpty()) {
        emit calendarUpdateFailed(tr("Task list name is required."), generation);
        return;
    }

    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, calendarHref);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/xml; charset=utf-8"));

    const QString normalizedColor = colorValue(color);
    QString colorXml;
    if (!normalizedColor.isEmpty()) {
        colorXml = QStringLiteral("<x1:calendar-color xmlns:x1=\"http://apple.com/ns/ical/\">%1</x1:calendar-color>")
            .arg(escapeXml(normalizedColor));
    }

    const QByteArray body = QStringLiteral(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<d:propertyupdate xmlns:d=\"DAV:\">"
        "<d:set><d:prop><d:displayname>%1</d:displayname>%2</d:prop></d:set>"
        "</d:propertyupdate>")
        .arg(escapeXml(displayName), colorXml)
        .toUtf8();

    QNetworkReply *reply = manager.sendCustomRequest(request, QByteArrayLiteral("PROPPATCH"), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if (status >= 200 && status < 300) {
            emit calendarUpdated(generation);
            return;
        }
        if (status > 0) {
            emit calendarUpdateFailed(tr("Task list update failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit calendarUpdateFailed(tr("Task list update failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::deleteCalendar(int generation,
                                   const QString &serverUrl,
                                   const QString &userName,
                                   const QString &secret,
                                   const QString &calendarHref)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || calendarHref.trimmed().isEmpty()) {
        emit calendarDeleteFailed(tr("Task list delete request is incomplete."), generation);
        return;
    }

    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, calendarHref);
    QNetworkReply *reply = manager.sendCustomRequest(request, QByteArrayLiteral("DELETE"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        if ((status >= 200 && status < 300) || status == 404 || status == 410) {
            emit calendarDeleted(generation);
            return;
        }
        if (status > 0) {
            emit calendarDeleteFailed(tr("Task list delete failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit calendarDeleteFailed(tr("Task list delete failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::moveTask(int generation,
                             const QString &serverUrl,
                             const QString &userName,
                             const QString &secret,
                             const QString &sourceHref,
                             const QString &destinationHref)
{
    const QString source = sourceHref.trimmed();
    const QString destination = destinationHref.trimmed();
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || source.isEmpty() || destination.isEmpty()) {
        emit taskMoveFailed(tr("Task move request is incomplete."), generation);
        return;
    }

    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, source);
    request.setRawHeader("Destination", absoluteCalendarUrl(serverUrl, destination).toUtf8());
    request.setRawHeader("Overwrite", "F");

    QNetworkReply *reply = manager.sendCustomRequest(request, QByteArrayLiteral("MOVE"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation, source, destination]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString etag = QString::fromUtf8(reply->rawHeader("ETag"));
        reply->deleteLater();

        if (status >= 200 && status < 300) {
            emit taskMoved(generation, source, destination, etag);
            return;
        }
        if (status == 409 || status == 412) {
            emit taskMoveFailed(tr("Task could not be moved because the destination list changed. Refresh tasks and try again."), generation);
            return;
        }
        if (status > 0) {
            emit taskMoveFailed(tr("Task move failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit taskMoveFailed(tr("Task move failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::lookupUser(int generation,
                               const QString &serverUrl,
                               const QString &userName,
                               const QString &secret)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty()) {
        emit userLookupFailed(tr("Account credentials are incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, QStringLiteral("/ocs/v2.php/cloud/user?format=json"));
    request.setRawHeader("OCS-APIRequest", "true");

    QNetworkReply *reply = requestManager->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        requestManager->deleteLater();

        if (status >= 200 && status < 300) {
            emit userLookupLoaded(QString::fromUtf8(body), generation);
            return;
        }
        if (status > 0) {
            emit userLookupFailed(tr("User lookup failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit userLookupFailed(tr("User lookup failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::loadCalendars(int generation,
                                  const QString &serverUrl,
                                  const QString &userName,
                                  const QString &secret,
                                  const QString &calendarHomeHref)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || calendarHomeHref.trimmed().isEmpty()) {
        emit calendarsLoadFailed(tr("Tasks calendar request is incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, calendarHomeHref);
    request.setRawHeader("Depth", "1");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/xml; charset=utf-8"));

    const QByteArray body = QByteArrayLiteral("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:cs=\"http://calendarserver.org/ns/\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\" xmlns:x1=\"http://apple.com/ns/ical/\"><d:prop><d:displayname/><cs:getctag/><c:supported-calendar-component-set/><x1:calendar-color/></d:prop></d:propfind>");
    QNetworkReply *reply = requestManager->sendCustomRequest(request, QByteArrayLiteral("PROPFIND"), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation, calendarHomeHref]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        requestManager->deleteLater();

        if (status >= 200 && status < 300) {
            emit calendarsLoaded(QString::fromUtf8(body), calendarHomeHref, generation);
            return;
        }
        if (status > 0) {
            emit calendarsLoadFailed(tr("Tasks calendar request failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit calendarsLoadFailed(tr("Tasks calendar request failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::loadTasks(int generation,
                              const QString &serverUrl,
                              const QString &userName,
                              const QString &secret,
                              const QString &calendarHref,
                              const QString &calendarTitle)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || calendarHref.trimmed().isEmpty()) {
        emit tasksLoadFailed(tr("Tasks request is incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, calendarHref);
    request.setRawHeader("Depth", "1");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/xml; charset=utf-8"));

    const QByteArray body = QByteArrayLiteral("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop></d:propfind>");
    QNetworkReply *reply = requestManager->sendCustomRequest(request, QByteArrayLiteral("PROPFIND"), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation, calendarTitle, calendarHref]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        requestManager->deleteLater();

        if (status >= 200 && status < 300) {
            emit tasksLoaded(calendarTitle, calendarHref, QString::fromUtf8(body), generation);
            return;
        }
        if (status > 0) {
            emit tasksLoadFailed(tr("Tasks request failed with HTTP %1.").arg(status), generation);
            return;
        }
        emit tasksLoadFailed(tr("Tasks request failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::putTask(int generation,
                            const QString &serverUrl,
                            const QString &userName,
                            const QString &secret,
                            const QString &taskHref,
                            const QString &body,
                            const QString &etag,
                            bool ifNoneMatch,
                            const QString &kind)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || taskHref.trimmed().isEmpty() || body.isEmpty()) {
        emit taskPutFailed(kind, tr("Task update data is incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, taskHref);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("text/calendar; charset=utf-8"));
    if (ifNoneMatch) {
        request.setRawHeader("If-None-Match", "*");
    } else if (!etag.trimmed().isEmpty()) {
        request.setRawHeader("If-Match", etag.trimmed().toUtf8());
    }

    QNetworkReply *reply = requestManager->put(request, body.toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation, kind, taskHref]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString responseEtag = QString::fromUtf8(reply->rawHeader("ETag"));
        reply->deleteLater();
        requestManager->deleteLater();

        if (status > 0) {
            emit taskPutFinished(kind, taskHref, responseEtag, status, generation);
            return;
        }
        emit taskPutFailed(kind, tr("Task update failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::deleteTaskObject(int generation,
                                     const QString &serverUrl,
                                     const QString &userName,
                                     const QString &secret,
                                     const QString &taskHref,
                                     const QString &etag)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || taskHref.trimmed().isEmpty()) {
        emit taskDeleteFailed(tr("Task delete data is incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, taskHref);
    if (!etag.trimmed().isEmpty()) {
        request.setRawHeader("If-Match", etag.trimmed().toUtf8());
    }

    QNetworkReply *reply = requestManager->deleteResource(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();
        requestManager->deleteLater();

        if (status > 0) {
            emit taskDeleteFinished(status, generation);
            return;
        }
        emit taskDeleteFailed(tr("Task delete failed because the network request could not be completed."), generation);
    });
}

void CalDavNetwork::fetchTaskObject(int generation,
                                    const QString &serverUrl,
                                    const QString &userName,
                                    const QString &secret,
                                    const QString &taskHref,
                                    const QString &kind)
{
    if (normalizedServerUrl(serverUrl).isEmpty() || userName.isEmpty() || secret.isEmpty() || taskHref.trimmed().isEmpty()) {
        emit taskFetchFailed(kind, tr("Task request is incomplete."), generation);
        return;
    }

    QNetworkAccessManager *requestManager = isolatedManager();
    QNetworkRequest request = authorizedRequest(serverUrl, userName, secret, taskHref);
    request.setRawHeader("Depth", "0");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/xml; charset=utf-8"));

    const QByteArray body = QByteArrayLiteral("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop></d:propfind>");
    QNetworkReply *reply = requestManager->sendCustomRequest(request, QByteArrayLiteral("PROPFIND"), body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestManager, generation, kind]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray responseBody = reply->readAll();
        reply->deleteLater();
        requestManager->deleteLater();

        if (status > 0) {
            emit taskFetched(kind, QString::fromUtf8(responseBody), status, generation);
            return;
        }
        emit taskFetchFailed(kind, tr("Task request failed because the network request could not be completed."), generation);
    });
}

QNetworkAccessManager *CalDavNetwork::isolatedManager()
{
    return new QNetworkAccessManager(this);
}

QNetworkRequest CalDavNetwork::authorizedRequest(const QString &serverUrl,
                                                 const QString &userName,
                                                 const QString &secret,
                                                 const QString &calendarHref) const
{
    QUrl url(absoluteCalendarUrl(serverUrl, calendarHref));
    if (!userName.isEmpty()) {
        url.setUserName(userName);
    }
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", "Basic " + QByteArray(QString(userName + QStringLiteral(":") + secret).toUtf8()).toBase64());
    request.setRawHeader("Connection", "close");
    return request;
}

QString CalDavNetwork::absoluteCalendarUrl(const QString &serverUrl, const QString &calendarHref) const
{
    const QString href = calendarHref.trimmed();
    if (href.startsWith(QStringLiteral("http://")) || href.startsWith(QStringLiteral("https://"))) {
        return href;
    }
    return normalizedServerUrl(serverUrl) + href;
}
