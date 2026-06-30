#ifndef CALDAVNETWORK_H
#define CALDAVNETWORK_H

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>

class CalDavNetwork : public QObject
{
    Q_OBJECT

public:
    explicit CalDavNetwork(QObject *parent = nullptr);

    Q_INVOKABLE void createCalendar(int generation,
                                    const QString &serverUrl,
                                    const QString &userName,
                                    const QString &secret,
                                    const QString &title);
    Q_INVOKABLE void updateCalendar(int generation,
                                    const QString &serverUrl,
                                    const QString &userName,
                                    const QString &secret,
                                    const QString &calendarHref,
                                    const QString &title,
                                    const QString &color);
    Q_INVOKABLE void deleteCalendar(int generation,
                                    const QString &serverUrl,
                                    const QString &userName,
                                    const QString &secret,
                                    const QString &calendarHref);
    Q_INVOKABLE void moveTask(int generation,
                              const QString &serverUrl,
                              const QString &userName,
                              const QString &secret,
                              const QString &sourceHref,
                              const QString &destinationHref);
    Q_INVOKABLE void lookupUser(int generation,
                                const QString &serverUrl,
                                const QString &userName,
                                const QString &secret);
    Q_INVOKABLE void loadCalendars(int generation,
                                   const QString &serverUrl,
                                   const QString &userName,
                                   const QString &secret,
                                   const QString &calendarHomeHref);
    Q_INVOKABLE void loadTasks(int generation,
                               const QString &serverUrl,
                               const QString &userName,
                               const QString &secret,
                               const QString &calendarHref,
                               const QString &calendarTitle);
    Q_INVOKABLE void loadTrashCollections(int generation,
                                          const QString &serverUrl,
                                          const QString &userName,
                                          const QString &secret,
                                          const QString &calendarHomeHref);
    Q_INVOKABLE void loadTrashObjects(int generation,
                                      const QString &serverUrl,
                                      const QString &userName,
                                      const QString &secret,
                                      const QString &trashBinHref);
    Q_INVOKABLE void restoreTrashItem(int generation,
                                      const QString &serverUrl,
                                      const QString &userName,
                                      const QString &secret,
                                      const QString &trashItemHref,
                                      const QString &trashBinHref);
    Q_INVOKABLE void putTask(int generation,
                             const QString &serverUrl,
                             const QString &userName,
                             const QString &secret,
                             const QString &taskHref,
                             const QString &body,
                             const QString &etag,
                             bool ifNoneMatch,
                             const QString &kind);
    Q_INVOKABLE void deleteTaskObject(int generation,
                                      const QString &serverUrl,
                                      const QString &userName,
                                      const QString &secret,
                                      const QString &taskHref,
                                      const QString &etag);
    Q_INVOKABLE void fetchTaskObject(int generation,
                                     const QString &serverUrl,
                                     const QString &userName,
                                     const QString &secret,
                                     const QString &taskHref,
                                     const QString &kind);

signals:
    void calendarCreated(int generation);
    void calendarCreateFailed(const QString &message, int generation);
    void calendarUpdated(int generation);
    void calendarUpdateFailed(const QString &message, int generation);
    void calendarDeleted(int generation);
    void calendarDeleteFailed(const QString &message, int generation);
    void taskMoved(int generation, const QString &sourceHref, const QString &destinationHref, const QString &etag);
    void taskMoveFailed(const QString &message, int generation);
    void userLookupLoaded(const QString &responseText, int generation);
    void userLookupFailed(const QString &message, int generation);
    void calendarsLoaded(const QString &responseText, const QString &calendarHomeHref, int generation);
    void calendarsLoadFailed(const QString &message, int generation);
    void tasksLoaded(const QString &calendarTitle, const QString &calendarHref, const QString &responseText, int generation);
    void tasksLoadFailed(const QString &message, int generation);
    void trashCollectionsLoaded(const QString &responseText, const QString &calendarHomeHref, int generation);
    void trashCollectionsLoadFailed(const QString &message, int generation);
    void trashObjectsLoaded(const QString &responseText, const QString &trashBinHref, int generation);
    void trashObjectsLoadFailed(const QString &message, int generation);
    void trashItemRestored(const QString &trashItemHref, int generation);
    void trashItemRestoreFailed(const QString &message, int generation);
    void taskPutFinished(const QString &kind, const QString &href, const QString &etag, int status, int generation);
    void taskPutFailed(const QString &kind, const QString &message, int generation);
    void taskDeleteFinished(int status, int generation);
    void taskDeleteFailed(const QString &message, int generation);
    void taskFetched(const QString &kind, const QString &responseText, int status, int generation);
    void taskFetchFailed(const QString &kind, const QString &message, int generation);

private:
    QNetworkAccessManager manager;
    QNetworkAccessManager *isolatedManager();
    QNetworkRequest authorizedRequest(const QString &serverUrl,
                                      const QString &userName,
                                      const QString &secret,
                                      const QString &calendarHref = QString()) const;
    QString absoluteCalendarUrl(const QString &serverUrl, const QString &calendarHref) const;
};

#endif
