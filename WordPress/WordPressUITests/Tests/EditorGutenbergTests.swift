import XCTest

class EditorGutenbergTests: XCTestCase {
    private var editorScreen: BlockEditorScreen!

    override func setUp() {
        setUpTestSuite()

        _ = LoginFlow.loginIfNeeded(siteUrl: WPUITestCredentials.testWPcomSiteAddress, email: WPUITestCredentials.testWPcomUserEmail, password: WPUITestCredentials.testWPcomPassword)
        editorScreen = EditorFlow
            .gotoMySiteScreen()
            .tabBar.gotoBlockEditorScreen()
    }

    override func tearDownWithError() throws {
        takeScreenshotOfFailedTest()
        if editorScreen != nil && !TabNavComponent.isVisible() {
            EditorFlow.returnToMainEditorScreen()
            editorScreen.closeEditor()
        }
        try LoginFlow.logoutIfNeeded()
        try super.tearDownWithError()
    }

    func testTextPostPublish() {
        let title = getRandomPhrase()
        let content = getRandomContent()
        editorScreen
            .dismissNotificationAlertIfNeeded(.accept)
            .enterTextInTitle(text: title)
            .addParagraphBlock(withText: content)
            .publish()
            .viewPublishedPost(withTitle: title)
            .verifyEpilogueDisplays(postTitle: title, siteAddress: WPUITestCredentials.testWPcomSitePrimaryAddress)
            .done()
    }

    func testBasicPostPublish() {
        let title = getRandomPhrase()
        let content = getRandomContent()
        let category = getCategory()
        let tag = getTag()
        editorScreen
            .dismissNotificationAlertIfNeeded(.accept)
            .enterTextInTitle(text: title)
            .addParagraphBlock(withText: content)
            .addImage()
            .openPostSettings()
            .selectCategory(name: category)
            .addTag(name: tag)
            .setFeaturedImage()
            .verifyPostSettings(withCategory: category, withTag: tag, hasImage: true)
            .removeFeatureImage()
            .verifyPostSettings(withCategory: category, withTag: tag, hasImage: false)
            .setFeaturedImage()
            .verifyPostSettings(withCategory: category, withTag: tag, hasImage: true)
            .closePostSettings()
        BlockEditorScreen().publish()
            .viewPublishedPost(withTitle: title)
            .verifyEpilogueDisplays(postTitle: title, siteAddress: WPUITestCredentials.testWPcomSitePrimaryAddress)
            .done()
    }
}
