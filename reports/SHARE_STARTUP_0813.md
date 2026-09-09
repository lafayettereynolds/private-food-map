# Share draft startup routing — 0813

Normal launch defaults to Map. Old pending imports previously auto-opened Add on each cold start until a restaurant was saved. Introduced persisted optional presentedAt, backward compatible with existing queue. Presentation retains the draft; explicit resharing resets presentation, saving consumes it. Hybrid startup selects only unpresented drafts; manual Add can retrieve retained drafts. Native rollback auto-presentation follows the same rule.

Five Task09PendingImportTests pass, including persistence/relaunch, retained payload, explicit resharing, consume, expiry and invalid input. Final Private/DebugPrivatePreview build signature, extension and purity gate PASS. Hybrid staged bundle retained unchanged from0812. Source fingerprint now includes TasteMapShared as well.

Installed2026090813 and launched, then read AppGroup queue on physical iPhone:2 retained drafts,2 presented,0 awaiting presentation. Relaunched20:12:29. Source997adfec07bc2f71e9f75f5e1f8da828b7f7733584f1ea83f5c84bd24cbd56af; HYBRID_DEVELOPMENT device identity confirmed. Exact visible map frame still requires user observation; no screenshot claimed. No personal data reset/deletion, purchase, cutover or upload.

## Device acceptance
Lafayette confirmed “好了 正常了” after0813 installation/relaunch. Ordinary startup
to Map without repeated Add Restaurant redirection: REAL DEVICE PASS.
