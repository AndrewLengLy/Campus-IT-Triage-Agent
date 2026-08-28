/**
 * Coverage for ITDeskAuditService: SLA resolution from Custom Metadata, field clipping, and
 * the deliberate rule that audit logging never throws into the student-facing path.
 *
 * The append-only guarantee on the object itself is covered by CampusITInteractionGuardTest.
 */
@IsTest
private class ITDeskAuditServiceTest {
    @IsTest
    static void firstResponseDue_readsHoursFromTheSlaRuleForThePriority() {
        ITDeskAuditService.slaOverrides = new List<IT_SLA_Rule__mdt>{
            new IT_SLA_Rule__mdt(Priority__c = 'High', First_Response_Hours__c = 4),
            new IT_SLA_Rule__mdt(Priority__c = 'Medium', First_Response_Hours__c = 16),
            new IT_SLA_Rule__mdt(Priority__c = 'Low', First_Response_Hours__c = 40)
        };

        assertDueWithinAnHourOf(4, ITDeskAuditService.firstResponseDue('High'), 'High');
        assertDueWithinAnHourOf(16, ITDeskAuditService.firstResponseDue('Medium'), 'Medium');
        assertDueWithinAnHourOf(40, ITDeskAuditService.firstResponseDue('Low'), 'Low');
        assertDueWithinAnHourOf(
            40,
            ITDeskAuditService.firstResponseDue('  low  '),
            'Priority matching must ignore case and surrounding whitespace'
        );
    }

    @IsTest
    static void firstResponseDue_fallsBackToSixteenHoursWhenNoRuleApplies() {
        ITDeskAuditService.slaOverrides = new List<IT_SLA_Rule__mdt>{
            new IT_SLA_Rule__mdt(Priority__c = 'High', First_Response_Hours__c = 4)
        };

        assertDueWithinAnHourOf(
            16,
            ITDeskAuditService.firstResponseDue(null),
            'A blank priority defaults to the Medium target'
        );
        assertDueWithinAnHourOf(
            16,
            ITDeskAuditService.firstResponseDue('Critical'),
            'A priority with no configured rule falls back to the default target'
        );
    }

    @IsTest
    static void firstResponseDue_ignoresRulesWithNoConfiguredHours() {
        ITDeskAuditService.slaOverrides = new List<IT_SLA_Rule__mdt>{
            new IT_SLA_Rule__mdt(Priority__c = 'High', First_Response_Hours__c = null),
            null
        };

        assertDueWithinAnHourOf(
            16,
            ITDeskAuditService.firstResponseDue('High'),
            'A rule with no hours must not produce a null or zero due date'
        );
    }

    @IsTest
    static void newInteraction_normalizesAndClipsEveryStoredField() {
        Campus_IT_Interaction__c row = ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_SELF_SERVICE,
            ITDeskAuditService.OUTCOME_MATCHED,
            true,
            's 1000-0001',
            null,
            'n'.repeat(60),
            'c'.repeat(60),
            'a'.repeat(120),
            'Matched a known-issue guide.'
        );

        Assert.areEqual(
            'S10000001',
            row.Student_ID__c,
            'Student IDs must be stored normalized so the trail can be joined on them.'
        );
        Assert.areEqual(40, row.Case_Number__c.length(), 'Case Number must fit its 40 character field.');
        Assert.areEqual(40, row.Category__c.length(), 'Category must fit its 40 character field.');
        Assert.areEqual(80, row.Article_Title__c.length(), 'Article Title must fit its 80 character field.');
        Assert.isTrue(row.Success__c, 'Success must reflect the flag passed in.');
    }

    @IsTest
    static void newInteraction_toleratesNullsWithoutLosingTheRow() {
        Campus_IT_Interaction__c row = ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_STATUS,
            ITDeskAuditService.OUTCOME_NOT_FOUND,
            null,
            null,
            null,
            null,
            null,
            null,
            null
        );

        Assert.areEqual(ITDeskAuditService.ACTION_STATUS, row.Action_Type__c);
        Assert.areEqual(ITDeskAuditService.OUTCOME_NOT_FOUND, row.Outcome__c);
        Assert.isFalse(row.Success__c, 'A null success flag must store as false, never as null.');
        Assert.isNull(row.Student_ID__c);

        Test.startTest();
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>{ row });
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'A row with only the required fields must still be written.'
        );
    }

    @IsTest
    static void log_skipsNullAndIncompleteRows() {
        Campus_IT_Interaction__c missingOutcome = new Campus_IT_Interaction__c(
            Action_Type__c = ITDeskAuditService.ACTION_STATUS
        );
        Campus_IT_Interaction__c missingAction = new Campus_IT_Interaction__c(
            Outcome__c = ITDeskAuditService.OUTCOME_FOUND
        );
        Campus_IT_Interaction__c complete = ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_STATUS,
            ITDeskAuditService.OUTCOME_FOUND,
            true,
            'S10000001',
            null,
            '00001234',
            'Network',
            null,
            'Ticket found.'
        );

        Test.startTest();
        ITDeskAuditService.log(null);
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>());
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>{ null, missingOutcome, missingAction, complete });
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'Only the row carrying both required picklists may be written.'
        );
    }

    @IsTest
    static void log_neverThrowsIntoTheStudentFacingPath() {
        Campus_IT_Interaction__c invalidPicklist = ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_STATUS,
            'Not_A_Configured_Outcome',
            true,
            'S10000001',
            null,
            null,
            null,
            null,
            'This row cannot be saved.'
        );

        Test.startTest();
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>{ invalidPicklist });
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'An unsaveable row is dropped rather than written.'
        );
        // Reaching this line is the assertion: a failed audit write must not propagate an
        // exception to the caller, because a student should never lose their ticket over
        // a logging problem. The tradeoff is discussed in ARCHITECTURE.md.
    }

    private static void assertDueWithinAnHourOf(Integer expectedHours, Datetime actual, String label) {
        Datetime lowerBound = Datetime.now().addHours(expectedHours - 1);
        Datetime upperBound = Datetime.now().addHours(expectedHours + 1);
        Assert.isTrue(
            actual > lowerBound && actual < upperBound,
            label + ': first response should be due about ' + expectedHours + ' hours out, got ' + actual
        );
    }
}
