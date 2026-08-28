// Seeds the sample students and a realistic spread of campus IT traffic.
// Idempotent: re-running reports what is already there instead of duplicating it.
//
//   sf apex run --file scripts/apex/seedSampleData.apex --target-org campus-it-dev

ITDeskDemoData.SeedResult result = ITDeskDemoData.seed();
System.debug(LoggingLevel.INFO, result.describe());
System.debug(LoggingLevel.INFO, 'Open the Campus IT app to review the Cases, queues, and interaction audit trail.');
