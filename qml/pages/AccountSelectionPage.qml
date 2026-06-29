import QtQuick 2.7
import "qrc:/NextCommon" as NextCommon

NextCommon.AccountPage {
    id: page

    property var appController

    appName: appController.appName
    logPrefix: "NextTasks"
    appApplicationId: "nexttasks.cloudsite_nexttasks"
    nextcloudServiceId: "nexttasks.cloudsite_nexttasks_nextcloud"
    owncloudServiceId: "nexttasks.cloudsite_nexttasks_owncloud"

    onAccountAuthorized: function(accountId, displayName, providerId, serviceId, serverUrl, avatarUrl) {
        if (page.appController && page.appController.accountChanged) {
            page.appController.accountChanged(accountId, displayName, providerId, serviceId, serverUrl, avatarUrl)
        }
    }
}
