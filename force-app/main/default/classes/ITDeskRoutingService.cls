/**
 * Shared Campus IT routing and lookup helpers.
 *
 * Production orgs should drive category → queue mapping from
 * IT_Category_Queue_Map__mdt so admins can change routing without a deploy.
 * Tests disable metadata (useCustomMetadataRouting = false) or inject
 * metadataOverrides so they never depend on packaged queue DeveloperNames.
 */
public with sharing class ITDeskRoutingService {
    public static final String PRIORITY_HIGH = 'High';
    public static final String PRIORITY_MEDIUM = 'Medium';
    public static final String PRIORITY_LOW = 'Low';

    private static final String QUEUE_NETWORK = 'Campus_IT_Network';
    private static final String QUEUE_HARDWARE = 'Campus_IT_Hardware';
    private static final String QUEUE_SOFTWARE = 'Campus_IT_Software';
    private static final String QUEUE_IDENTITY = 'Campus_IT_Identity';
    private static final String QUEUE_GENERAL = 'Campus_IT_General';

    /**
     * When true, Custom Metadata rows win over the in-memory fallback map.
     * Tests that install CIT_Test_* queues must set this to false (or supply overrides).
     */
    @TestVisible
    private static Boolean useCustomMetadataRouting = true;

    /**
     * In-memory CMT stand-ins. When non-null, used instead of getAll().
     */
    @TestVisible
    private static List<IT_Category_Queue_Map__mdt> metadataOverrides;

    @TestVisible
    private static String defaultQueueDeveloperName = QUEUE_GENERAL;

    /**
     * Fallback keyword map used when no Custom Metadata rows are available.
     */
    @TestVisible
    private static Map<String, String> categoryKeywordToQueueDevName = new Map<String, String>{
        'network' => QUEUE_NETWORK,
        'wifi' => QUEUE_NETWORK,
        'vpn' => QUEUE_NETWORK,
        'hardware' => QUEUE_HARDWARE,
        'laptop' => QUEUE_HARDWARE,
        'printer' => QUEUE_HARDWARE,
        'software' => QUEUE_SOFTWARE,
        'application' => QUEUE_SOFTWARE,
        'license' => QUEUE_SOFTWARE,
        'email' => QUEUE_SOFTWARE,
        'outlook' => QUEUE_SOFTWARE,
        'account' => QUEUE_IDENTITY,
        'password' => QUEUE_IDENTITY,
        'login' => QUEUE_IDENTITY,
        'identity' => QUEUE_IDENTITY,
        'mfa' => QUEUE_IDENTITY
    };

    /**
     * Maps free-text urgency onto standard Case Priority values.
     */
    public static String resolvePriority(String urgency) {
        if (String.isBlank(urgency)) {
            return PRIORITY_MEDIUM;
        }

        Set<String> tokens = tokenize(urgency);
        if (
            tokens.contains('critical') ||
            tokens.contains('emergency') ||
            tokens.contains('urgent') ||
            tokens.contains('high') ||
            tokens.contains('p1') ||
            tokens.contains('p2') ||
            tokens.contains('sev1')
        ) {
            return PRIORITY_HIGH;
        }
        if (tokens.contains('low') || tokens.contains('p4') || tokens.contains('sev4')) {
            return PRIORITY_LOW;
        }
        return PRIORITY_MEDIUM;
    }

    /**
     * Resolves a queue DeveloperName from category keywords. Unmatched → default queue.
     */
    public static String resolveQueueDeveloperName(String category) {
        Map<String, String> keywordMap = activeKeywordMap();
        String fallback = activeDefaultQueueDeveloperName();
        if (String.isBlank(category) || keywordMap == null || keywordMap.isEmpty()) {
            return fallback;
        }

        String normalized = category.toLowerCase();
        for (String keyword : keywordMap.keySet()) {
            if (String.isNotBlank(keyword) && normalized.contains(keyword.toLowerCase())) {
                return keywordMap.get(keyword);
            }
        }
        return fallback;
    }

    public static Map<String, Group> queryQueuesByDeveloperName(Set<String> developerNames) {
        Map<String, Group> queuesByDeveloperName = new Map<String, Group>();
        if (developerNames == null || developerNames.isEmpty()) {
            return queuesByDeveloperName;
        }

        for (Group queue : [
            SELECT Id, Name, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName IN :developerNames
        ]) {
            queuesByDeveloperName.put(queue.DeveloperName, queue);
        }
        return queuesByDeveloperName;
    }

    public static Map<Id, Group> queryQueuesById(Set<Id> queueIds) {
        Map<Id, Group> queuesById = new Map<Id, Group>();
        if (queueIds == null || queueIds.isEmpty()) {
            return queuesById;
        }

        for (Group queue : [
            SELECT Id, Name, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND Id IN :queueIds
        ]) {
            queuesById.put(queue.Id, queue);
        }
        return queuesById;
    }

    public static Map<String, Contact> queryContactsByStudentId(Set<String> studentIds) {
        Map<String, Contact> contactsByStudentId = new Map<String, Contact>();
        if (studentIds == null || studentIds.isEmpty()) {
            return contactsByStudentId;
        }

        Set<String> lookupIds = expandStudentIds(studentIds);
        if (lookupIds.isEmpty()) {
            return contactsByStudentId;
        }

        for (Contact person : [
            SELECT Id, Name, Student_ID__c
            FROM Contact
            WHERE Student_ID__c IN :lookupIds
        ]) {
            indexByStudentId(contactsByStudentId, person.Student_ID__c, person);
        }
        return contactsByStudentId;
    }

    public static Map<String, List<Case>> queryOpenCasesByStudentId(Set<String> studentIds) {
        return queryCasesByStudentId(studentIds, true);
    }

    /**
     * All Cases for the given student IDs, open tickets first.
     */
    public static Map<String, List<Case>> queryCasesByStudentId(Set<String> studentIds) {
        return queryCasesByStudentId(studentIds, false);
    }

    private static Map<String, List<Case>> queryCasesByStudentId(Set<String> studentIds, Boolean openOnly) {
        Map<String, List<Case>> casesByStudentId = new Map<String, List<Case>>();
        Set<String> lookupIds = expandStudentIds(studentIds);
        if (lookupIds.isEmpty()) {
            return casesByStudentId;
        }

        if (openOnly) {
            for (Case ticket : [
                SELECT
                    Id,
                    CaseNumber,
                    Status,
                    Priority,
                    OwnerId,
                    Owner.Name,
                    Student_ID__c,
                    Subject,
                    IsClosed,
                    LastModifiedDate,
                    IT_Category__c,
                    SuppliedEmail,
                    ContactId
                FROM Case
                WHERE Student_ID__c IN :lookupIds AND IsClosed = FALSE
                ORDER BY LastModifiedDate DESC
            ]) {
                addCaseForStudent(casesByStudentId, ticket);
            }
        } else {
            for (Case ticket : [
                SELECT
                    Id,
                    CaseNumber,
                    Status,
                    Priority,
                    OwnerId,
                    Owner.Name,
                    Student_ID__c,
                    Subject,
                    IsClosed,
                    LastModifiedDate,
                    IT_Category__c,
                    SuppliedEmail,
                    ContactId
                FROM Case
                WHERE Student_ID__c IN :lookupIds
                ORDER BY IsClosed ASC, LastModifiedDate DESC
            ]) {
                addCaseForStudent(casesByStudentId, ticket);
            }
        }
        return casesByStudentId;
    }

    public static Map<String, Case> queryCasesByNumber(Set<String> caseNumbers) {
        Map<String, Case> byNumber = new Map<String, Case>();
        Set<String> keys = new Set<String>();
        if (caseNumbers == null) {
            return byNumber;
        }
        for (String input : caseNumbers) {
            keys.addAll(caseNumberLookupKeys(input));
        }
        if (keys.isEmpty()) {
            return byNumber;
        }

        for (Case ticket : [
            SELECT
                Id,
                CaseNumber,
                Status,
                Priority,
                OwnerId,
                Owner.Name,
                Student_ID__c,
                Subject,
                IsClosed,
                LastModifiedDate,
                IT_Category__c,
                SuppliedEmail,
                ContactId
            FROM Case
            WHERE CaseNumber IN :keys
        ]) {
            indexCaseByNumber(byNumber, ticket);
        }
        return byNumber;
    }

    public static Case findCaseByNumber(Map<String, Case> byNumber, String input) {
        if (byNumber == null || String.isBlank(input)) {
            return null;
        }
        for (String key : caseNumberLookupKeys(input)) {
            if (byNumber.containsKey(key)) {
                return byNumber.get(key);
            }
        }
        return null;
    }

    /**
     * Reuses an open Case when it is already on the target queue, or when the
     * subject still reflects the same category (covers user-owned tickets).
     */
    public static Case findReusableOpenCase(
        String studentId,
        String category,
        String queueDeveloperName,
        Map<String, List<Case>> openCasesByStudentId,
        Map<Id, Group> queuesById
    ) {
        if (String.isBlank(studentId) || openCasesByStudentId == null) {
            return null;
        }

        List<Case> openCases = casesForStudent(openCasesByStudentId, studentId);
        if (openCases == null || openCases.isEmpty()) {
            return null;
        }

        String canonicalCategory = resolveCategoryLabel(category);
        String categoryNeedle = String.isBlank(category) ? 'general' : category.trim().toLowerCase();
        for (Case ticket : openCases) {
            Group ownerQueue = queuesById == null ? null : queuesById.get(ticket.OwnerId);
            if (ownerQueue != null && ownerQueue.DeveloperName == queueDeveloperName) {
                return ticket;
            }
            if (
                String.isNotBlank(ticket.IT_Category__c) &&
                ticket.IT_Category__c.equalsIgnoreCase(canonicalCategory)
            ) {
                return ticket;
            }
            if (String.isNotBlank(ticket.Subject) && ticket.Subject.toLowerCase().contains(categoryNeedle)) {
                return ticket;
            }
        }
        return null;
    }

    private static Map<String, String> activeKeywordMap() {
        List<IT_Category_Queue_Map__mdt> rows = routingRows();
        if (!rows.isEmpty()) {
            Map<String, String> mapped = new Map<String, String>();
            for (IT_Category_Queue_Map__mdt row : rows) {
                addKeyword(mapped, row.Keyword__c, row.Queue_Developer_Name__c);
                if (String.isNotBlank(row.Aliases__c)) {
                    for (String alias : row.Aliases__c.split(',')) {
                        addKeyword(mapped, alias, row.Queue_Developer_Name__c);
                    }
                }
            }
            return mapped;
        }
        return categoryKeywordToQueueDevName == null
            ? new Map<String, String>()
            : categoryKeywordToQueueDevName;
    }

    private static String activeDefaultQueueDeveloperName() {
        for (IT_Category_Queue_Map__mdt row : routingRows()) {
            if (row.Is_Default__c && String.isNotBlank(row.Queue_Developer_Name__c)) {
                return row.Queue_Developer_Name__c;
            }
        }
        return defaultQueueDeveloperName;
    }

    private static List<IT_Category_Queue_Map__mdt> routingRows() {
        if (metadataOverrides != null) {
            return metadataOverrides;
        }
        if (!useCustomMetadataRouting) {
            return new List<IT_Category_Queue_Map__mdt>();
        }
        return IT_Category_Queue_Map__mdt.getAll().values();
    }

    private static void addKeyword(Map<String, String> mapped, String keyword, String queueDeveloperName) {
        if (String.isBlank(keyword) || String.isBlank(queueDeveloperName)) {
            return;
        }
        mapped.put(keyword.trim().toLowerCase(), queueDeveloperName.trim());
    }

    /**
     * Canonical category label stored on Case.IT_Category__c (Network, Hardware, Software, Account, General).
     */
    public static String resolveCategoryLabel(String category) {
        return labelForQueueDeveloperName(resolveQueueDeveloperName(category));
    }

    /**
     * Strips spaces/punctuation and uppercases so "s 10000001" matches S10000001.
     */
    public static String normalizeStudentId(String studentId) {
        if (String.isBlank(studentId)) {
            return null;
        }
        String compact = studentId.trim().replaceAll('[^A-Za-z0-9]', '').toUpperCase();
        return String.isBlank(compact) ? null : compact;
    }

    /**
     * Normalizes spoken issue text for known-issue matching (wi-fi → wifi, won't → wont).
     */
    public static String normalizeIssueText(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value
            .toLowerCase()
            .replace('wi-fi', 'wifi')
            .replace('won\'t', 'wont')
            .replace('can\'t', 'cant')
            .replace('isn\'t', 'isnt');
    }

    public static Set<String> caseNumberLookupKeys(String input) {
        Set<String> keys = new Set<String>();
        if (String.isBlank(input)) {
            return keys;
        }
        String trimmed = input.trim();
        keys.add(trimmed);
        String digits = trimmed.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) {
            return keys;
        }
        keys.add(digits);
        String stripped = digits.replaceFirst('^0+', '');
        if (String.isNotBlank(stripped)) {
            keys.add(stripped);
            keys.add(stripped.leftPad(8, '0'));
        }
        return keys;
    }

    public static Set<String> tokenize(String value) {
        Set<String> tokens = new Set<String>();
        if (String.isBlank(value)) {
            return tokens;
        }
        String normalized = value.trim().toLowerCase();
        tokens.add(normalized);
        for (String part : normalized.split('[^a-z0-9]+')) {
            if (String.isNotBlank(part)) {
                tokens.add(part);
            }
        }
        return tokens;
    }

    /**
     * Published Case Comments are visible to the student on customer-facing Case channels.
     */
    public static CaseComment newPublishedComment(Id caseId, String body) {
        if (caseId == null || String.isBlank(body)) {
            return null;
        }
        String commentBody = body.length() > 4000 ? body.substring(0, 4000) : body;
        return new CaseComment(ParentId = caseId, CommentBody = commentBody, IsPublished = true);
    }

    public static void insertPublishedComments(List<CaseComment> comments) {
        if (comments == null || comments.isEmpty()) {
            return;
        }
        List<CaseComment> toInsert = new List<CaseComment>();
        for (CaseComment comment : comments) {
            if (comment != null && comment.ParentId != null && String.isNotBlank(comment.CommentBody)) {
                toInsert.add(comment);
            }
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    private static String labelForQueueDeveloperName(String developerName) {
        if (String.isBlank(developerName)) {
            return 'General';
        }
        String normalized = developerName.toLowerCase();
        if (normalized.contains('network')) {
            return 'Network';
        }
        if (normalized.contains('hardware')) {
            return 'Hardware';
        }
        if (normalized.contains('software')) {
            return 'Software';
        }
        if (normalized.contains('identity')) {
            return 'Account';
        }
        return 'General';
    }

    private static Set<String> expandStudentIds(Set<String> studentIds) {
        Set<String> keys = new Set<String>();
        if (studentIds == null) {
            return keys;
        }
        for (String raw : studentIds) {
            if (String.isBlank(raw)) {
                continue;
            }
            keys.add(raw.trim());
            String normalized = normalizeStudentId(raw);
            if (normalized != null) {
                keys.add(normalized);
            }
        }
        return keys;
    }

    private static void indexByStudentId(Map<String, Contact> contactsByStudentId, String studentId, Contact person) {
        if (person == null) {
            return;
        }
        if (String.isNotBlank(studentId)) {
            contactsByStudentId.put(studentId, person);
        }
        String normalized = normalizeStudentId(studentId);
        if (normalized != null) {
            contactsByStudentId.put(normalized, person);
        }
    }

    private static void addCaseForStudent(Map<String, List<Case>> casesByStudentId, Case ticket) {
        if (ticket == null) {
            return;
        }
        Set<String> keys = new Set<String>();
        if (String.isNotBlank(ticket.Student_ID__c)) {
            keys.add(ticket.Student_ID__c);
        }
        String normalized = normalizeStudentId(ticket.Student_ID__c);
        if (normalized != null) {
            keys.add(normalized);
        }
        for (String key : keys) {
            if (!casesByStudentId.containsKey(key)) {
                casesByStudentId.put(key, new List<Case>());
            }
            casesByStudentId.get(key).add(ticket);
        }
    }

    public static Boolean studentIdsMatch(String left, String right) {
        String normalizedLeft = normalizeStudentId(left);
        String normalizedRight = normalizeStudentId(right);
        return normalizedLeft != null && normalizedLeft == normalizedRight;
    }

    public static List<Case> casesForStudent(Map<String, List<Case>> casesByStudentId, String studentId) {
        if (casesByStudentId == null) {
            return null;
        }
        String normalized = normalizeStudentId(studentId);
        if (normalized != null && casesByStudentId.containsKey(normalized)) {
            return casesByStudentId.get(normalized);
        }
        if (String.isNotBlank(studentId) && casesByStudentId.containsKey(studentId.trim())) {
            return casesByStudentId.get(studentId.trim());
        }
        return null;
    }

    private static void indexCaseByNumber(Map<String, Case> byNumber, Case ticket) {
        if (ticket == null || String.isBlank(ticket.CaseNumber)) {
            return;
        }
        byNumber.put(ticket.CaseNumber, ticket);
        for (String key : caseNumberLookupKeys(ticket.CaseNumber)) {
            byNumber.put(key, ticket);
        }
    }
}
