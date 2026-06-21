import QtQuick 2.7
import Ubuntu.OnlineAccounts 0.1
import Qt.labs.settings 1.0
import "AuthCore.js" as AuthCore

Item {
    id: adapter

    property bool pendingServiceHandle: false
    property int cachedAccountId: 0
    property string cachedServiceId: ""
    property string cachedServerUrl: ""
    property string cachedUserName: ""
    property string cachedSecret: ""
    property int currentAccountId: 0
    property string currentProviderId: ""
    property string currentServiceId: ""
    property string currentServerUrl: ""
    property int pendingAuthAccountId: 0
    property string pendingAuthServiceId: ""
    property string pendingAuthServerUrl: ""
    property var pendingCallback: null
    property bool envTestAuthEnabled: typeof desktopTestAuthEnabled !== "undefined" && desktopTestAuthEnabled
    property string envTestServerUrl: typeof desktopTestServerUrl !== "undefined" ? desktopTestServerUrl : ""
    property string envTestUserName: typeof desktopTestUserName !== "undefined" ? desktopTestUserName : ""
    property string envTestSecret: typeof desktopTestSecret !== "undefined" ? desktopTestSecret : ""

    signal authenticated(string userName, string secret, string serverUrl, int accountId, string serviceId)
    signal failed(string message)

    Settings {
        id: accountSettings
        category: "account"
        property int accountId: 0
        property string displayName: ""
        property string providerId: ""
        property string serviceId: ""
        property string serverUrl: ""
    }

    AccountServiceModel {
        id: accountServices
        includeDisabled: true

        onCountChanged: {
            if (adapter.pendingServiceHandle) {
                adapter.authenticate()
            }
        }
    }

    AccountService {
        id: accountService

        onAuthenticated: {
            var data = reply && reply.data ? reply.data : reply
            var userName = adapter.firstValue(data, ["UserName", "Username", "userName", "username"])
            var secret = adapter.firstValue(data, ["Secret", "Password", "password", "secret"])
            var token = adapter.firstValue(data, ["AccessToken", "Token", "token"])

            console.log(
                "NextTasks Account auth success"
                + " accountId=" + adapter.effectiveAccountId()
                + " providerId=" + adapter.effectiveProviderId()
                + " serviceId=" + adapter.effectiveServiceId()
                + " dataKeys=" + adapter.objectKeys(data).join(",")
                + " hasUserName=" + adapter.hasValue(userName)
                + " userHash=" + AuthCore.maskedIdentity(userName)
                + " hasPasswordOrSecret=" + adapter.hasValue(secret)
                + " hasToken=" + adapter.hasValue(token)
            )

            if (!userName || !secret) {
                adapter.failed(i18n.tr("Authentication succeeded, but the required Online Accounts credentials were not available."))
                return
            }

            if (!adapter.pendingAuthMatchesCurrent()) {
                console.log(
                    "NextTasks Account auth ignored stale response"
                    + " pendingAccountId=" + adapter.pendingAuthAccountId
                    + " currentAccountId=" + adapter.effectiveAccountId()
                    + " pendingServiceId=" + adapter.pendingAuthServiceId
                    + " currentServiceId=" + adapter.effectiveServiceId()
                )
                return
            }

            adapter.cachedAccountId = adapter.pendingAuthAccountId
            adapter.cachedServiceId = adapter.pendingAuthServiceId
            adapter.cachedServerUrl = adapter.pendingAuthServerUrl
            adapter.cachedUserName = userName
            adapter.cachedSecret = secret

            adapter.authenticated(userName, secret, adapter.cachedServerUrl, adapter.cachedAccountId, adapter.cachedServiceId)
            if (adapter.pendingCallback) {
                var callback = adapter.pendingCallback
                adapter.pendingCallback = null
                callback(userName, secret, adapter.cachedServerUrl, adapter.cachedAccountId, adapter.cachedServiceId)
            }
        }

        onAuthenticationError: {
            var message = error && error.message ? error.message : JSON.stringify(error)
            if (!adapter.pendingAuthMatchesCurrent()) {
                console.log("NextTasks Account auth ignored stale error")
                return
            }
            console.log(
                "NextTasks Account auth error"
                + " accountId=" + adapter.effectiveAccountId()
                + " providerId=" + adapter.effectiveProviderId()
                + " serviceId=" + adapter.effectiveServiceId()
                + " message=" + message
            )
            adapter.failed(i18n.tr("Authentication failed: %1").arg(message))
        }
    }

    Timer {
        id: authenticateAfterHandleTimer
        interval: 80
        repeat: false
        onTriggered: accountService.authenticate({})
    }

    function authenticate() {
        if (envTestAuthEnabled) {
            var testServerUrl = normalizeServerUrl(envTestServerUrl)
            if (testServerUrl.length === 0 || envTestUserName.length === 0 || envTestSecret.length === 0) {
                failed(i18n.tr("Desktop test credentials are incomplete."))
                return
            }

            cachedAccountId = -1
            cachedServiceId = "desktop-test-env"
            cachedServerUrl = testServerUrl
            cachedUserName = envTestUserName
            cachedSecret = envTestSecret
            console.log("NextTasks Account auth using desktop test environment credentials serverUrlConfigured=" + hasValue(testServerUrl))
            authenticated(cachedUserName, cachedSecret, cachedServerUrl, cachedAccountId, cachedServiceId)
            if (pendingCallback) {
                var callback = pendingCallback
                pendingCallback = null
                callback(cachedUserName, cachedSecret, cachedServerUrl, cachedAccountId, cachedServiceId)
            }
            return
        }

        if (effectiveAccountId() <= 0 || effectiveServiceId().length === 0) {
            failed(i18n.tr("No account selected. Open Account first and authorize a Nextcloud account."))
            return
        }

        var serverUrl = normalizeServerUrl(effectiveServerUrl())
        if (serverUrl.length === 0) {
            failed(i18n.tr("No server URL configured. Open Account and authorize the OS account."))
            return
        }

        if (hasCachedCredentials(serverUrl)) {
            console.log(
                "NextTasks Account auth reused in-memory credentials"
                + " accountId=" + effectiveAccountId()
                + " providerId=" + effectiveProviderId()
                + " serviceId=" + effectiveServiceId()
                + " serverUrlConfigured=" + hasValue(serverUrl)
            )
            authenticated(cachedUserName, cachedSecret, cachedServerUrl, cachedAccountId, cachedServiceId)
            if (pendingCallback) {
                var callback = pendingCallback
                pendingCallback = null
                callback(cachedUserName, cachedSecret, cachedServerUrl, cachedAccountId, cachedServiceId)
            }
            return
        }

        var handle = findSelectedAccountService()
        if (!handle) {
            if (accountServices.count === 0) {
                pendingServiceHandle = true
                failed(i18n.tr("Waiting for Online Accounts..."))
            } else {
                failed(i18n.tr("Selected Online Accounts service was not found. Open Account and verify the account again."))
            }
            return
        }

        pendingServiceHandle = false
        accountService.objectHandle = handle
        pendingAuthAccountId = effectiveAccountId()
        pendingAuthServiceId = effectiveServiceId()
        pendingAuthServerUrl = serverUrl
        console.log(
            "NextTasks Account auth requesting"
            + " accountId=" + effectiveAccountId()
            + " providerId=" + effectiveProviderId()
            + " serviceId=" + effectiveServiceId()
            + " serverUrlConfigured=" + hasValue(serverUrl)
        )
        authenticateAfterHandleTimer.restart()
    }

    function withCredentials(callback) {
        pendingCallback = callback
        authenticate()
    }

    function setAccount(accountId, providerId, serviceId, serverUrl) {
        var normalizedServerUrl = normalizeServerUrl(serverUrl)
        var accountChanged = currentAccountId !== accountId
            || currentProviderId !== (providerId || "")
            || currentServiceId !== (serviceId || "")
            || currentServerUrl !== normalizedServerUrl

        if (accountChanged) {
            pendingServiceHandle = false
            pendingCallback = null
            cachedAccountId = 0
            cachedServiceId = ""
            cachedServerUrl = ""
            cachedUserName = ""
            cachedSecret = ""
            pendingAuthAccountId = 0
            pendingAuthServiceId = ""
            pendingAuthServerUrl = ""
            authenticateAfterHandleTimer.stop()
            accountService.objectHandle = null
        }

        currentAccountId = accountId
        currentProviderId = providerId || ""
        currentServiceId = serviceId || ""
        currentServerUrl = normalizedServerUrl
    }

    function hasCachedCredentials(serverUrl) {
        return cachedAccountId === effectiveAccountId()
            && cachedServiceId === effectiveServiceId()
            && cachedServerUrl === serverUrl
            && cachedUserName.length > 0
            && cachedSecret.length > 0
    }

    function pendingAuthMatchesCurrent() {
        return pendingAuthAccountId === effectiveAccountId()
            && pendingAuthServiceId === effectiveServiceId()
            && pendingAuthServerUrl === normalizeServerUrl(effectiveServerUrl())
    }

    function findSelectedAccountService() {
        var accountId = effectiveAccountId()
        var providerIdSetting = effectiveProviderId()
        var serviceIdSetting = effectiveServiceId()
        for (var i = 0; i < accountServices.count; ++i) {
            if (accountServices.get(i, "accountId") === accountId) {
                var handle = accountServices.get(i, "accountServiceHandle")
                accountService.objectHandle = handle
                var provider = accountService.provider || {}
                var service = accountService.service || {}
                var providerId = provider.id || accountServices.get(i, "providerName")
                var serviceId = service.id || accountServices.get(i, "serviceName")

                if (providerId === providerIdSetting && serviceId === serviceIdSetting) {
                    return handle
                }
            }
        }
        return null
    }

    function effectiveAccountId() {
        return currentAccountId > 0 ? currentAccountId : accountSettings.accountId
    }

    function effectiveProviderId() {
        return currentProviderId.length > 0 ? currentProviderId : accountSettings.providerId
    }

    function effectiveServiceId() {
        return currentServiceId.length > 0 ? currentServiceId : accountSettings.serviceId
    }

    function effectiveServerUrl() {
        return currentServerUrl.length > 0 ? currentServerUrl : accountSettings.serverUrl
    }

    function normalizeServerUrl(value) {
        return AuthCore.normalizeServerUrl(value)
    }

    function firstValue(value, names) {
        return AuthCore.firstValue(value, names)
    }

    function objectKeys(value) {
        return AuthCore.objectKeys(value)
    }

    function hasValue(value) {
        return AuthCore.hasValue(value)
    }

}
