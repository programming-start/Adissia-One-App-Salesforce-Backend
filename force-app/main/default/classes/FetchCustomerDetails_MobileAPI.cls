/**
 * FetchUserDetails API
 * Purpose : Data for the customer profile page, looked up by the phone number
 *           the customer provides (?phoneNumber=...).
 *
 * Phone is matched against the four applicant phone fields on Booking__c
 * (1st mobile / 1st alternate / 2nd mobile / 2nd alternate).
 *
 * Returns:
 *   firstApplicantName, district, firstApplicantMobile  (from the latest booking)
 *   propertiesPurchased  - count of the customer's bookings at Stage 'Registration'
 *   requestCount         - Build Companion + Property Resale requests (via Customer_Master__c)
 *   withAdissiaSince      - earliest Booking_Date__c across the customer's bookings
 */
@RestResource(urlMapping='/FetchCustomerDetails/*')
global without sharing class FetchCustomerDetails_MobileAPI {

    private static final String REGISTRATION_STAGE = 'Registration';

    @HttpGet
    global static void fetchUserDetails() {
        RestRequest request = RestContext.request;
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'FetchCustomerDetails_MobileAPI';

        try {
            String phoneNumber = request.params.get('phoneNumber');
            apexLog.Request__c = 'phoneNumber=' + phoneNumber;

            if (String.isBlank(phoneNumber)) {
                apexLog.response__c = 'Phone Number should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Phone Number should not be blank');
                return;
            }

            // All of the customer's bookings, matched on any of the four phone fields
            List<Booking__c> bookingList = [SELECT Id, First_Applicant_Name__c, District__c, Contact_Number__c, Stage__c, Registration_Done__c, Booking_Date__c FROM Booking__c WHERE Contact_Number__c = :phoneNumber OR Mobile_Alternate__c = :phoneNumber OR Contact_Number1__c = :phoneNumber OR Mobile_Alternate1__c = :phoneNumber ORDER BY Booking_Date__c ASC];

            if (bookingList.isEmpty()) {
                apexLog.response__c = 'No booking found for this phone number';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('No booking found for this phone number. Please contact Adissia.');
                return;
            }

            // Profile display fields - from the most recent booking
            Booking__c latestBooking = bookingList[0];

            // Properties purchased = bookings at the Registration stage; earliest booking date
            Integer propertiesPurchased = 0;
            Datetime earliestBookingDate = null;
            for (Booking__c booking : bookingList) {
                if (booking.Stage__c == REGISTRATION_STAGE && booking.Registration_Done__c == true) {
                    propertiesPurchased++;
                }
                if (booking.Booking_Date__c != null && (earliestBookingDate == null || booking.Booking_Date__c < earliestBookingDate)) {
                    earliestBookingDate = booking.Booking_Date__c;
                }
            }

            // Request count via the customer's Customer_Master__c (matched by phone)
            Integer requestCount = 0;
            String customerRecordName = '';
            List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE (Phone__c = :phoneNumber OR First_Applicant_Phone_Number__c = :phoneNumber OR First_Applicant_Alternate_Number__c = :phoneNumber OR Second_Applicant_Phone_Number__c = :phoneNumber OR Second_Applicant_Alternate_Number__c = :phoneNumber) AND isActive__c = TRUE LIMIT 1];
            if (!customerMasterList.isEmpty()) {
                Id customerId = customerMasterList[0].Id;
                customerRecordName = customerMasterList[0].Name;
                Integer buildCompanionCount = [SELECT COUNT() FROM Build_Companion_Request__c WHERE Customer_Master__c = :customerId];
                Integer resaleCount = [SELECT COUNT() FROM Re_Sale_Property__c WHERE Customer_Master__c = :customerId];
                requestCount = buildCompanionCount + resaleCount;
            }

            Map<String, Object> data = new Map<String, Object>{
                'firstApplicantName'   => safe(latestBooking.First_Applicant_Name__c),
                'district'             => safe(latestBooking.District__c),
                'firstApplicantMobile' => safe(latestBooking.Contact_Number__c),
                'propertiesPurchased'  => propertiesPurchased,
                'requestCount'         => requestCount,
                'withAdissiaSince'     => earliestBookingDate != null ? String.valueOf(earliestBookingDate) : '',
                'customerID'           => customerRecordName
            };

            apexLog.response__c = 'User details fetched successfully for ' + phoneNumber;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'User details fetched successfully',
                'data'    => data
            }));

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    // Returns '' instead of null so the JSON never carries null strings.
    private static String safe(String value) {
        return value == null ? '' : value;
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}