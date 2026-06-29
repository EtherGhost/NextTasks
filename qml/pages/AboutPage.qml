import QtQuick 2.7
import "../NextCommon" as NextCommon

NextCommon.AboutPage {
    property var appController
    readonly property string currentAppVersion: typeof nexttasksAppVersion !== "undefined" ? nexttasksAppVersion : "development"

    appName: appController.appName
    appVersion: currentAppVersion
    appDescription: appController.appDescription
    logoSource: "qrc:/assets/logo.svg"
}
