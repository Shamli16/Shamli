@IsTest
private class ExternalUploadServiceTest {

    // Utility: invoke REST class with provided JSON body
    private static RestResponse invokeWithBody(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/external/upload';
        req.httpMethod = 'POST';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        Test.startTest();
        ExternalUploadService.upsertUploadRecord();
        Test.stopTest();
        return RestContext.response;
    }

    @IsTest static void test_success_minimal_required_fields() {
        // Create related records for potential lookup fields
        Account client = new Account(Name = 'Client A');
        insert client;

        // Build payload that exercises top-level mappings + Agreement/Application/Payment
        String json = JSON.serialize(new Map<String, Object>{
            'Update Category' => 'CatA',
            'Record Type' => 'TypeA',
            'Type' => 'T1',
            'Placement Tier' => 'Tier1',
            'Default Type' => 'Def1',
            'Contractual Fee' => '$1,234.56',
            'Agreement' => new List<Object>{ new Map<String,Object>{
                'Client' => String.valueOf(client.Id),
                'Account Name' => 'Acme Inc',
                'Alias' => 'ACME',
                'Date of Underlying Agreement' => '2024-01-15',
                'Account Billing Street' => '1 Main St',
                'Account Phone' => '555-111-2222',
                'Original Funded Amount' => '$2,000.00',
                'Shipping Street' => '123 Lane,Metropolis,NY-10001',
                'Guarantor #1 Title' => 'Mr',
                'Guarantor #1 Salutation' => 'Sir',
                'Guarantor #1 First Name' => 'John',
                'Guarantor #1 Last Name' => 'Doe',
                'Guarantor #1 Street' => '10 A St',
                'Guarantor #1 City' => 'Town',
                'Guarantor #1 State' => 'CA',
                'Guarantor #1 Zip Code' => '90210'
            }},
            'Application' => new List<Object>{ new Map<String,Object>{
                'Account Name' => 'Acme Inc',
                'Alias' => 'ACME',
                'Federal Tax ID' => '12-3456789',
                'Date of Incorporation' => '01/20/2020',
                'Account Phone' => '555-111-3333',
                'Date of Birth1' => '1990-12-31',
                'Guarantor #1 Social Security Number' => '111-22-3333',
                'Guarantor #1 Phone' => '555-444-5555',
                'Guarantor #1 Email' => 'john@example.com',
                'Guarantor #1 Street' => '10 A St',
                'Guarantor #1 City' => 'Town',
                'Guarantor #1 State' => 'CA',
                'Guarantor #1 Zip Code' => '90210'
            }},
            'Payment_History' => new List<Object>{ new Map<String,Object>{
                'External Client ID' => 'EXT-1',
                'Principal' => '$100.00',
                'Funding Date' => '2024/02/01',
                'Date of Last Payment' => '02-15-2024'
            }}
        });

        RestResponse res = invokeWithBody(json);
        System.assertEquals(201, res.statusCode, 'Expected Created');
        String body = res.responseBody != null ? res.responseBody.toString() : null;
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(body);
        System.assertEquals(true, (Boolean)resp.get('success'));
        System.assertNotEquals(null, resp.get('id'));

        // Confirm record inserted
        Upload__c inserted = [SELECT Id, Account_Shipping_Street__c, Account_Shipping_City__c, Account_Shipping_State__c, Account_Shipping_Zip_Code__c, Contractual_Fees__c, Principal__c FROM Upload__c WHERE Id = :((String)resp.get('id')) LIMIT 1];
        System.assertEquals('123 Lane', inserted.Account_Shipping_Street__c);
        System.assertEquals('Metropolis', inserted.Account_Shipping_City__c);
        System.assertEquals('NY', inserted.Account_Shipping_State__c);
        System.assertEquals('10001', inserted.Account_Shipping_Zip_Code__c);
        System.assertEquals(Decimal.valueOf('1234.56'), inserted.Contractual_Fees__c);
        System.assertEquals(Decimal.valueOf('100.00'), inserted.Principal__c);
    }

    @IsTest static void test_empty_body_returns_400() {
        RestResponse res = invokeWithBody(null);
        System.assertEquals(400, res.statusCode);
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, (Boolean)resp.get('success'));
        System.assert(((String)resp.get('message')).contains('Empty request body'));
    }

    @IsTest static void test_bad_json_returns_400() {
        String bad = '{"Update Category": '; // invalid JSON
        RestResponse res = invokeWithBody(bad);
        System.assertEquals(400, res.statusCode);
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false, (Boolean)resp.get('success'));
        System.assert(((String)resp.get('message')).startsWith('Error:'));
    }

    @IsTest static void test_shipping_fallback_when_no_commas() {
        String json = JSON.serialize(new Map<String, Object>{
            'Agreement' => new List<Object>{ new Map<String,Object>{
                'Shipping Street' => 'No parsing available'
            }}
        });
        RestResponse res = invokeWithBody(json);
        System.assertEquals(201, res.statusCode);
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id recId = (Id)resp.get('id');
        Upload__c u = [SELECT Account_Shipping_Street__c, Account_Shipping_City__c, Account_Shipping_State__c, Account_Shipping_Zip_Code__c FROM Upload__c WHERE Id = :recId];
        System.assertEquals('No parsing available', u.Account_Shipping_Street__c);
        System.assertEquals(null, u.Account_Shipping_City__c);
        System.assertEquals(null, u.Account_Shipping_State__c);
        System.assertEquals(null, u.Account_Shipping_Zip_Code__c);
    }

    @IsTest static void test_date_parsing_variants_and_currency_noise() {
        String json = JSON.serialize(new Map<String, Object>{
            'Contractual Fee' => 'USD 9,999.99',
            'Agreement' => new List<Object>{ new Map<String,Object>{
                'Date of Underlying Agreement' => '03/05/2024',
                'Original Funded Amount' => '$2,500',
                'Shipping Street' => '500 Road,Gotham,NJ 07001'
            }},
            'Payment_History' => new List<Object>{ new Map<String,Object>{
                'Funding Date' => '2024-03-06',
                'Date of Last Payment' => '03/07/2024'
            }}
        });
        RestResponse res = invokeWithBody(json);
        System.assertEquals(201, res.statusCode);
        Map<String,Object> resp = (Map<String,Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Upload__c u = [SELECT Account_Shipping_Street__c, Account_Shipping_City__c, Account_Shipping_State__c, Account_Shipping_Zip_Code__c, Contractual_Fees__c, Original_Funded_Amount__c, Funding_Date__c, Date_of_Last_Payment__c, Date_of_Underlying_Agreement__c FROM Upload__c WHERE Id = :((String)resp.get('id'))];
        System.assertEquals('500 Road', u.Account_Shipping_Street__c);
        System.assertEquals('Gotham', u.Account_Shipping_City__c);
        System.assertEquals('NJ', u.Account_Shipping_State__c);
        System.assertEquals('07001', u.Account_Shipping_Zip_Code__c);
        System.assertEquals(Decimal.valueOf('9999.99'), u.Contractual_Fees__c);
        System.assertEquals(Decimal.valueOf('2500'), u.Original_Funded_Amount__c);
        System.assertNotEquals(null, u.Funding_Date__c);
        System.assertNotEquals(null, u.Date_of_Last_Payment__c);
        System.assertNotEquals(null, u.Date_of_Underlying_Agreement__c);
    }
}
