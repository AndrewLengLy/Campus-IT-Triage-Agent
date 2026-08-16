/**
 * Agentforce action that searches campus IT known-issue articles before a Case
 * is created. Atlas should call this first; escalate only when there is no match
 * or Requires Escalation is true and first-aid steps were already tried.
 */
public with sharing class ITDeskSelfService {
    @TestVisible
    private static List<IT_Known_Issue__mdt> knownIssueOverrides;

    public class SelfServiceRequest {
        @InvocableVariable(
            required=true
            label='Issue Description'
            description='Natural-language description of the student IT problem. Used to match campus known-issue articles (WiFi, password, VPN, Outlook, MFA, laptop power).'
        )
        public String issueDescription;

        @InvocableVariable(
            label='Category'
            description='Optional IT category to improve ranking. Examples: Network, Hardware, Software, Account, Email.'
        )
        public String category;

        @InvocableVariable(
            label='Student ID'
            description='Optional campus student identifier for the audit trail. Not required to find a guide.'
        )
        public String studentId;
    }

    public class SelfServiceResult {
        @InvocableVariable(
            label='Match Found'
            description='True when a known-issue article matched. If false, escalate or ask a clarifying question.'
        )
        public Boolean isMatch;

        @InvocableVariable(label='Article Title' description='Title of the matched campus IT guide.')
        public String title;

        @InvocableVariable(
            label='Resolution Steps'
            description='Numbered troubleshooting steps to walk the student through.'
        )
        public String resolutionSteps;

        @InvocableVariable(
            label='Requires Escalation'
            description='True when the article is only first aid and a technician is still required, or when no article matched.'
        )
        public Boolean requiresEscalation;

        @InvocableVariable(label='Matched Keywords' description='Keywords that produced the match, for your reasoning only.')
        public String matchedKeywords;

        @InvocableVariable(label='Message' description='Student-facing sentence introducing the guide or saying none was found.')
        public String message;

        @InvocableVariable(label='Next Steps' description='Whether to walk through steps, then escalate, or escalate now.')
        public String nextSteps;
    }

    @InvocableMethod(
        label='Find Campus IT Self-Service Guide'
        description='Searches campus IT known-issue articles for a student problem and returns troubleshooting steps. Call this before escalating. Use when the student describes WiFi, password, VPN, email, MFA, or similar issues that might be resolved in-chat. If no article matches, or the student already tried the steps, escalate a ticket.'
        category='Campus IT'
    )
    public static List<SelfServiceResult> findGuide(List<SelfServiceRequest> requests) {
        List<SelfServiceResult> results = new List<SelfServiceResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<IT_Known_Issue__mdt> catalog = activeIssues();
        for (SelfServiceRequest request : requests) {
            if (request == null || String.isBlank(request.issueDescription)) {
                results.add(buildValidationFailure());
                continue;
            }
            results.add(matchIssue(request, catalog));
        }
        logLookups(requests, results);
        return results;
    }

    private static SelfServiceResult buildValidationFailure() {
        SelfServiceResult result = new SelfServiceResult();
        result.isMatch = false;
        result.requiresEscalation = false;
        result.message = 'I need a short description of the problem before I can look up a campus IT guide.';
        result.nextSteps = 'Ask the student what is not working, then retry this action.';
        return result;
    }

    private static SelfServiceResult matchIssue(SelfServiceRequest request, List<IT_Known_Issue__mdt> catalog) {
        IT_Known_Issue__mdt best;
        Integer bestScore = 0;
        String bestHits = '';

        String haystack = request.issueDescription;
        if (String.isNotBlank(request.category)) {
            haystack += ' ' + request.category;
        }
        String normalized = ITDeskRoutingService.normalizeIssueText(haystack);
        Set<String> tokens = ITDeskRoutingService.tokenize(normalized);

        for (IT_Known_Issue__mdt article : catalog) {
            if (article == null || String.isBlank(article.Keywords__c)) {
                continue;
            }

            Integer score = 0;
            List<String> hits = new List<String>();
            for (String rawKeyword : article.Keywords__c.split(',')) {
                String keyword = rawKeyword == null ? '' : rawKeyword.trim().toLowerCase();
                if (String.isBlank(keyword)) {
                    continue;
                }
                if (normalized.contains(keyword) || tokens.contains(keyword)) {
                    score++;
                    hits.add(keyword);
                }
            }
            if (score == 0) {
                continue;
            }
            if (String.isNotBlank(request.category) && String.isNotBlank(article.Category__c)
                && request.category.trim().equalsIgnoreCase(article.Category__c)) {
                score += 2;
            }
            if (score > bestScore) {
                bestScore = score;
                best = article;
                bestHits = String.join(hits, ', ');
            }
        }

        if (best == null) {
            SelfServiceResult none = new SelfServiceResult();
            none.isMatch = false;
            none.requiresEscalation = true;
            none.message = 'I do not have a self-service guide for that issue.';
            none.nextSteps = 'Ask one clarifying question if the description is vague. Otherwise escalate a Campus IT ticket.';
            return none;
        }

        SelfServiceResult result = new SelfServiceResult();
        result.isMatch = true;
        result.title = best.Title__c;
        result.resolutionSteps = best.Resolution_Steps__c;
        result.requiresEscalation = best.Requires_Escalation__c == true;
        result.matchedKeywords = bestHits;
        result.message = 'I found a campus IT guide: ' + best.Title__c + '.';
        if (result.requiresEscalation) {
            result.nextSteps = 'Share the first-aid steps, then escalate a ticket. A technician still needs to finish this.';
        } else {
            result.nextSteps = 'Walk the student through the resolution steps. If they already tried them or they still fail, escalate a Campus IT ticket.';
        }
        return result;
    }

    private static List<IT_Known_Issue__mdt> activeIssues() {
        List<IT_Known_Issue__mdt> source = knownIssueOverrides != null
            ? knownIssueOverrides
            : IT_Known_Issue__mdt.getAll().values();
        List<IT_Known_Issue__mdt> active = new List<IT_Known_Issue__mdt>();
        for (IT_Known_Issue__mdt article : source) {
            if (article != null && article.Is_Active__c != false) {
                active.add(article);
            }
        }
        return active;
    }

    private static void logLookups(List<SelfServiceRequest> requests, List<SelfServiceResult> results) {
        List<Campus_IT_Interaction__c> rows = new List<Campus_IT_Interaction__c>();
        for (Integer i = 0; i < results.size(); i++) {
            SelfServiceResult result = results[i];
            SelfServiceRequest request = i < requests.size() ? requests[i] : null;
            if (result == null) {
                continue;
            }
            String outcome = result.isMatch == true
                ? ITDeskAuditService.OUTCOME_MATCHED
                : ITDeskAuditService.OUTCOME_NO_MATCH;
            if (request == null || String.isBlank(request.issueDescription)) {
                outcome = ITDeskAuditService.OUTCOME_FAILED;
            }
            rows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_SELF_SERVICE,
                    outcome,
                    result.isMatch,
                    request == null ? null : request.studentId,
                    null,
                    null,
                    request == null ? null : request.category,
                    result.title,
                    result.message
                )
            );
        }
        ITDeskAuditService.log(rows);
    }
}
