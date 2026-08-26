/**
 * Class Name : VerifyUser_MobileAPI
 * API Name   : VerifyUser API
 * REST Method: POST
 * Purpose    : Validate a person by the phone number they enter, by matching it
    *           against any of the four applicant phone fields on Booking__c:
    *             - Contact_Number__c    (1st Applicant Mobile Number)
    *             - Mobile_Alternate__c  (1st Applicant Alternate Number)
    *             - Contact_Number1__c   (2nd Applicant Mobile Number)
    *             - Mobile_Alternate1__c (2nd Applicant Alternate Number)
 *                  Returns 200 if a matching Booking exists, otherwise a 400 with a message.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/VerifyUser/*')
global without sharing class VerifyUser_MobileAPI {

    @HttpPost
    global static void verifyUser() {
        RestRequest request = RestContext.request;
        String requestBody = request.requestBody.toString(); // Get the JSON body
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'VerifyUser_MobileAPI';
        apexLog.Request__c = requestBody;

        try {
            VerifyUserWrapper requestWrapper = (VerifyUserWrapper) JSON.deserialize(requestBody, VerifyUserWrapper.class);
            String phoneNumber = requestWrapper.phoneNumber;

            if (String.isBlank(phoneNumber)) {
                apexLog.response__c = 'Phone Number should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendResponse(400, false, 'Phone Number should not be blank');
                return;
            }

            // Query All Booking records for the given phone number in any of the four fields
            List<Booking__c> matchingBookingList = [SELECT Id FROM Booking__c WHERE Contact_Number__c = :phoneNumber OR Mobile_Alternate__c = :phoneNumber OR Contact_Number1__c = :phoneNumber OR Mobile_Alternate1__c = :phoneNumber LIMIT 1];
            if (matchingBookingList.isEmpty()) {
                apexLog.response__c = 'No booking found for this phone number';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendResponse(400, false, 'No booking found for this phone number. Please contact Adissia.');
                return;
            }

            apexLog.response__c = 'User verified successfully for ' + phoneNumber;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendResponse(200, true, 'User verified successfully');

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendResponse(400, false, 'Error: ' + caughtException.getMessage());
        }
    }

    public class VerifyUserWrapper {
        public String phoneNumber;
    }

    private static void sendResponse(Integer statusCode, Boolean success, String message) {
        RestResponse restResponse = RestContext.response;
        restResponse.statusCode = statusCode;
        restResponse.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{'success' => success, 'message' => message}));
    }
}