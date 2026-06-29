import QtQuick 2.7
import "../NextCommon" as NextCommon

NextCommon.LanguagePage {
    property var appController

    appName: appController.appName
    translationNotice: i18n.tr("Some translations are AI-assisted and not fully reviewed. You can help improve translations in the project repository.")
    languageOptions: [
        { "code": "", "label": i18n.tr("Follow system language"), "detail": i18n.tr("Default") },
        { "code": "en", "label": "English", "detail": i18n.tr("Built-in source language") },
        { "code": "sv", "label": "Svenska", "detail": i18n.tr("Initial translation") },
        { "code": "da", "label": "Dansk", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "de", "label": "Deutsch", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "es", "label": "Español", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "fi", "label": "Suomi", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "fr", "label": "Français", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "it", "label": "Italiano", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "nb", "label": "Norsk bokmål", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "nl", "label": "Nederlands", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "pl", "label": "Polski", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "ru", "label": "Русский", "detail": i18n.tr("AI-assisted starter translation") },
        { "code": "uk", "label": "Українська", "detail": i18n.tr("AI-assisted starter translation") }
    ]
}
