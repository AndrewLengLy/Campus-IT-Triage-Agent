/**
 * Behaviour coverage for ITDeskSelfService: matching a known-issue article, ranking when
 * several could apply, and telling the caller when a guide is only first aid.
 *
 * Failure modes live in ITDeskNegativePathTest; 200-record batches live in ITDeskBulkTest.
 */
@IsTest
private class ITDeskSelfServiceTest {
    @IsTest
    static void findGuide_returnsTheStepsForAMatchingArticle() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('I cannot stay on campus Wi-Fi in the library.', 'Network', 'S10000001')
            }
        );
        Test.stopTest();

        ITDeskSelfService.SelfServiceResult result = results[0];
        Assert.isTrue(result.isMatch, 'A spoken "Wi-Fi" must match the wifi article.');
        Assert.areEqual('Reconnect to campus WiFi', result.title);
        Assert.isTrue(String.isNotBlank(result.resolutionSteps), 'A match must carry steps the caller can read out.');
        Assert.isFalse(result.requiresEscalation, 'A self-serviceable guide must not push straight to a ticket.');
        Assert.isTrue(result.matchedKeywords.contains('wifi'), 'The caller needs to know why it matched.');
        Assert.isTrue(result.nextSteps.contains('Walk the student through'));

        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_SELF_SERVICE
                AND Outcome__c = :ITDeskAuditService.OUTCOME_MATCHED
            ],
            'A match must be audited so deflection can be measured.'
        );
        Assert.areEqual(
            'S10000001',
            [SELECT Student_ID__c FROM Campus_IT_Interaction__c LIMIT 1].Student_ID__c,
            'The lookup must be attributable to the student who asked.'
        );
    }

    @IsTest
    static void findGuide_flagsFirstAidArticlesThatStillNeedATechnician() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('My laptop has no power and will not start.', null, 'S10000002')
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isMatch);
        Assert.areEqual('Laptop will not power on', results[0].title);
        Assert.isTrue(
            results[0].requiresEscalation,
            'A first-aid-only guide must tell the caller a technician is still required.'
        );
        Assert.isTrue(results[0].nextSteps.contains('escalate'));
    }

    @IsTest
    static void findGuide_returnsNoMatchForAnIssueOutsideTheCatalog() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('The dining hall app crashed.', null, 'S10000003')
            }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isMatch, 'The catalog must not stretch to cover an unrelated problem.');
        Assert.isTrue(results[0].requiresEscalation, 'No guide means the student needs a person.');
        Assert.isNull(results[0].title);
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_NO_MATCH
            ],
            'A miss must be audited so catalog gaps become visible.'
        );
    }

    @IsTest
    static void findGuide_ignoresRetiredArticles() {
        ITDeskSelfService.knownIssueOverrides = new List<IT_Known_Issue__mdt>{
            ITDeskTestFactory.newKnownIssue('Retired wifi guide', 'wifi', 'Network', false, false),
            ITDeskTestFactory.newKnownIssue('Current wifi guide', 'wifi', 'Network', false, true)
        };

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('Campus wifi keeps dropping.', null, 'S10000001')
            }
        );
        Test.stopTest();

        Assert.areEqual(
            'Current wifi guide',
            results[0].title,
            'Deactivating an article in Custom Metadata must take it out of circulation.'
        );
    }

    @IsTest
    static void findGuide_prefersTheArticleWithMoreMatchingKeywords() {
        ITDeskSelfService.knownIssueOverrides = new List<IT_Known_Issue__mdt>{
            ITDeskTestFactory.newKnownIssue('Generic network guide', 'wifi', 'Network', false, true),
            ITDeskTestFactory.newKnownIssue(
                'Eduroam in residence halls',
                'wifi,eduroam,residence',
                'Network',
                false,
                true
            )
        };

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('Eduroam wifi drops in my residence hall.', null, 'S10000001')
            }
        );
        Test.stopTest();

        Assert.areEqual(
            'Eduroam in residence halls',
            results[0].title,
            'The more specific article, matching three keywords instead of one, must win.'
        );
        Assert.isTrue(results[0].matchedKeywords.contains('eduroam'));
    }

    @IsTest
    static void findGuide_keepsResultsAlignedAcrossAMixedBatch() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('I forgot my password.', 'Account', 'S10000001'),
                ITDeskTestFactory.selfService('The dining hall app crashed.', null, 'S10000002'),
                ITDeskTestFactory.selfService('   ', null, 'S10000003'),
                null
            }
        );
        Test.stopTest();

        Assert.areEqual(4, results.size(), 'Every request must get a result in its own position.');
        Assert.areEqual('Reset your campus password', results[0].title);
        Assert.isFalse(results[1].isMatch, 'The unmatched request must stay in position 1.');
        Assert.isFalse(results[2].isMatch);
        Assert.isTrue(
            results[2].nextSteps.contains('what is not working'),
            'A blank description must ask for one rather than escalating.'
        );
        Assert.isFalse(results[3].isMatch, 'A null request must not shift the others.');
    }
}
