# Unmanaged package (optional distribution)

This project is source-first. The path recruiters and other developers should use is `sf project deploy start` from the repo. Use an unmanaged package only when you want a click-to-install URL for a Developer Edition or Trailhead Playground that does not have the Salesforce CLI.

Unmanaged packages are a one-time drop. After install, the subscriber owns and can edit every component. You cannot push upgrades. Keep the packaging org alive; if that org is deleted, new installs of that upload can fail.

## Before you package

1. Deploy this repo to a **Developer Edition** org you control (not a scratch org you will throw away).
2. Run `sf apex run test --test-level RunLocalTests --code-coverage`. Coverage must stay at or above 75%.
3. Assign **Campus IT Triage** and run `scripts/apex/seedSampleData.apex` so you can verify the app before upload.
4. Confirm there are no hardcoded record IDs and no Connected Apps or secrets (this repo has none).

## Create and upload

1. In the packaging org: **Setup → Quick Find → Package Manager → New**.
2. Name: `Campus IT Service Desk Triage Agent`.
3. Leave **Managed** unchecked (unmanaged).
4. On **Components**, click **Add**. Add these types, then **View Dependencies** and add anything Salesforce requires:

   | Type | Members |
   | --- | --- |
   | Apex Class | All `ITDesk*` classes, including tests |
   | Apex Trigger | `CampusITInteractionGuard` |
   | Custom Application | `Campus_IT` |
   | Custom Object | `Campus_IT_Interaction__c`, `IT_Category_Queue_Map__mdt`, `IT_Known_Issue__mdt`, `IT_SLA_Rule__mdt` |
   | Custom Field | Case and Contact fields listed in `manifest/package.xml` |
   | Custom Metadata | All `IT_Category_Queue_Map.*`, `IT_Known_Issue.*`, `IT_SLA_Rule.*` records |
   | Custom Tab | `Campus_IT_Interaction__c` |
   | Compact Layout | `Campus_IT_Case`, `Campus_IT_Interaction` |
   | Page Layout | `Campus IT Case`, `Campus IT Interaction Layout` |
   | List View | Campus IT Case and Interaction views |
   | Permission Set | `Campus_IT_Triage_Agent` |
   | Queue | `Campus_IT_Network`, `Campus_IT_Hardware`, `Campus_IT_Software`, `Campus_IT_Identity`, `Campus_IT_General` |

5. Click **Upload**. Version name `1.0`, version number `1.0`.
6. Wait for the email. Copy the installation URL (`p0=04t...`).
7. Paste that URL into the README **Install from an unmanaged package** section when you have it. Do not invent a package ID.

Install URL shape:

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tXXXXXXXXXXXX
```

Sandbox / Trailhead Playground login uses `https://test.salesforce.com/packaging/installPackage.apexp?p0=04t...` only when the subscriber org is on a test instance. Most Developer Edition and production-login Playgrounds use `login.salesforce.com`.

## After someone installs

These do **not** travel with the package and must be done in the subscriber org:

1. Assign the **Campus IT Triage** permission set to the user the actions run as.
2. App Launcher → **Campus IT**.
3. Assign the **Campus IT Case** page layout and compact layout on Case (optional, recommended for demos).
4. Run `sf apex run --file scripts/apex/seedSampleData.apex` to seed the sample students and tickets.

## Why this repo is not a managed package

Managed packages need a Partner Business Org, a namespace, `global` invocables, and a security review before AppExchange. That is the right path for a commercial listing, not for an open-source portfolio drop. Unlocked packages (2GP) are a later option if you want versioned CLI installs without a namespace.
