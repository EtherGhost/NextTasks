.pragma library

function normalizeServerUrl(value) {
    if (!value) {
        return ""
    }

    var url = String(value).trim()
    if (url.length === 0) {
        return ""
    }
    while (url.length > 0 && url.charAt(url.length - 1) === "/") {
        url = url.slice(0, -1)
    }
    if (url.indexOf("http://") === 0 || url.indexOf("https://") === 0) {
        return url
    }
    return "https://" + url
}

function onlineAccountConfigured(accountId, serviceId, serverUrl) {
    return Number(accountId) > 0
        && String(serviceId || "").length > 0
        && normalizeServerUrl(serverUrl).length > 0
}

function firstValue(value, names) {
    if (!value) {
        return ""
    }

    for (var i = 0; i < names.length; ++i) {
        if (value[names[i]] !== undefined && value[names[i]] !== null && String(value[names[i]]).length > 0) {
            return String(value[names[i]])
        }
    }
    return ""
}

function objectKeys(value) {
    var keys = []
    if (!value) {
        return keys
    }

    for (var key in value) {
        keys.push(key)
    }
    return keys.sort()
}

function hasValue(value) {
    return value !== undefined && value !== null && String(value).length > 0 ? "true" : "false"
}

function stableHash(value) {
    var text = String(value || "")
    var hash = 0
    for (var i = 0; i < text.length; ++i) {
        hash = ((hash << 5) - hash + text.charCodeAt(i)) & 0x7fffffff
    }
    return hash.toString(36)
}

function maskedIdentity(value) {
    var text = String(value || "")
    if (text.length === 0) {
        return "none"
    }
    return "h" + stableHash(text)
}
