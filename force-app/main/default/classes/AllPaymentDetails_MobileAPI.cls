/**
 * Author     : Sivam V
 * Class Name : AllPaymentDetails_MobileAPI
 * API Name   : AllPaymentDetails API
 * REST Method: GET
 * Purpose    : Return all APPROVED payments (Receipt__c) across every booking made
 *              by the customer, looked up by Customer Id / AID (?customerId=AID3147).
 *              Per receipt returns: receiptId, receiptName, amount, paymentStatus,
 *              modeOfPayment, receiptDate, paymentReceivedDate, bookingName.
 *              Also returns totalPaid across all approved receipts.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/AllPaymentDetails/*')
global without sharing class AllPaymentDetails_MobileAPI {

    private static final String APPROVED_STATUS = 'Approved';

    @HttpGet
    global static void getAllPaymentDetails() {
        RestRequest request = RestContext.request;
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'AllPaymentDetails_MobileAPI';

        try {
            String customerId = request.params.get('customerId');
            apexLog.Request__c = 'customerId=' + customerId;

            if (String.isBlank(customerId)) {
                apexLog.response__c = 'Customer Id should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Customer Id should not be blank');
                return;
            }

            // Resolve the AID name to the Customer Master record
            List<Customer_Master__c> customerMasterList = [SELECT Id FROM Customer_Master__c WHERE Name = :customerId AND isActive__c = TRUE LIMIT 1];
            if (customerMasterList.isEmpty()) {
                apexLog.response__c = 'Customer Not Found';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Customer Not Found');
                return;
            }

            // All bookings of this customer
            List<Booking__c> bookingList = [SELECT Id FROM Booking__c WHERE Customer_Master__c = :customerMasterList[0].Id];
            if (bookingList.isEmpty()) {
                sendPaymentResponse(new List<PaymentData>(), 0);
                apexLog.response__c = 'No booking found for this customer';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                return;
            }

            Set<Id> bookingIds = new Set<Id>();
            for (Booking__c booking : bookingList) { bookingIds.add(booking.Id); }

            // All approved receipts across those bookings
            List<Receipt__c> receiptList = [SELECT Id, Name, Received_Amount__c, Approval_status__c,  Mode_of_Payment__c, Receipt_date__c, Payment_Received_Date__c, Booking_Name__c FROM Receipt__c WHERE Booking__c IN :bookingIds AND Approval_status__c = :APPROVED_STATUS ORDER BY Receipt_date__c DESC]; // Payment_Status__c : In Progress

            List<PaymentData> paymentDataList = new List<PaymentData>();
            Decimal totalPaid = 0;
            for (Receipt__c receipt : receiptList) {
                PaymentData paymentData = new PaymentData();
                paymentData.receiptId = receipt.Name;
                paymentData.amount = receipt.Received_Amount__c != null ? String.valueOf(receipt.Received_Amount__c) : '0';
                paymentData.approvalStatus = safe(receipt.Approval_status__c);
                // paymentData.paymentStatus = safe(receipt.Payment_Status__c);
                paymentData.modeOfPayment = safe(receipt.Mode_of_Payment__c);
                paymentData.receiptDate = receipt.Receipt_date__c != null ? String.valueOf(receipt.Receipt_date__c) : '';
                paymentData.paymentReceivedDate = receipt.Payment_Received_Date__c != null ? String.valueOf(receipt.Payment_Received_Date__c) : '';
                paymentData.bookingName = safe(receipt.Booking_Name__c);
                paymentDataList.add(paymentData);

                if (receipt.Received_Amount__c != null) { totalPaid += receipt.Received_Amount__c; }
            }

            sendPaymentResponse(paymentDataList, totalPaid);

            apexLog.response__c = 'Payment details fetched successfully for ' + customerId;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // ----------------------------------------------------------------- WRAPPERS -----------------------------------------------------------------------
    public class PaymentResponse {
        public Boolean success;
        public String message;
        public PaymentResponseData data;
    }
    public class PaymentResponseData {
        public String totalPaid;
        public List<PaymentData> payments;
    }
    public class PaymentData {
        public String receiptId;
        public String amount;
        public String approvalStatus;
        // public String paymentStatus;
        public String modeOfPayment;
        public String receiptDate;
        public String paymentReceivedDate;
        public String bookingName;
    }

    private static void sendPaymentResponse(List<PaymentData> payments, Decimal totalPaid) {
        PaymentResponse response = new PaymentResponse();
        response.success = true;
        response.message = 'Payment details fetched successfully';
        response.data = new PaymentResponseData();
        response.data.totalPaid = String.valueOf(totalPaid);
        response.data.payments = payments;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}