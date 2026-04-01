# Laravel 3DS2 Challenge Flow

A complete example of the 3DS2 challenge flow: initiate authentication (AReq), receive challenge required (`transStatus: C`), redirect to ACS, receive authentication result (CAVV + ECI), proceed with authorisation.

## Flow Diagram

```
Client                 Laravel                3DS Server              ACS
  |                       |                       |                    |
  |-- POST /payments/auth->|                       |                    |
  |                       |-- AReq --------------->|                    |
  |                       |<-- ARes (C) -----------|                    |
  |<-- 200 {acsUrl, etc}  |                       |                    |
  |                       |                       |                    |
  |-- redirect to ACS URL ---------------------------->               |
  |<--  ACS challenge UI -------------------------------------------- |
  |-- submit challenge ------------------------------------------------>|
  |                       |<-- CRes (Y/N/A/U) -----|                    |
  |                       |-- POST /payments/auth/callback             |
  |<-- 200 {cavv, eci}    |                       |                    |
  |                       |                       |                    |
  |-- POST /payments       |                       |                    |
  |                       |-- authorise (with CAVV + ECI) --> gateway  |
```

## Routes

```php
// routes/api.php
Route::prefix('v1')->middleware(['auth:sanctum', 'throttle:payments'])->group(function () {
    // Step 1: Initiate 3DS2 authentication
    Route::post('payments/authenticate', [ThreeDSController::class, 'initiate'])
        ->name('payments.3ds.initiate');

    // Step 2: ACS posts CRes back after challenge
    Route::post('payments/authenticate/callback', [ThreeDSController::class, 'callback'])
        ->name('payments.3ds.callback')
        ->withoutMiddleware('auth:sanctum'); // ACS posts here — no bearer token
});
```

## Controller

```php
<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Http\Requests\Payment\InitiateThreeDSRequest;
use App\Http\Requests\Payment\ThreeDSCallbackRequest;
use App\Services\ThreeDSService;
use Illuminate\Http\JsonResponse;

final class ThreeDSController
{
    public function __construct(
        private readonly ThreeDSService $threeDS,
    ) {}

    /**
     * Step 1: Initiate 3DS2 authentication.
     *
     * Returns one of:
     *   - { status: "authenticated", cavv, eci, dsTransId }  — frictionless flow, proceed to auth
     *   - { status: "challenge_required", acsUrl, creqToken, threeDSSessionData } — redirect to ACS
     *   - { status: "unavailable" }  — 3DS server returned U; caller should fall back to 3DS1
     */
    public function initiate(InitiateThreeDSRequest $request): JsonResponse
    {
        $result = $this->threeDS->initiate($request->validated());

        return response()->json($result);
    }

    /**
     * Step 2: Receive CRes from ACS after challenge.
     *
     * ACS HTTP-POSTs a base64url-encoded CRes value to this endpoint.
     * Extract CAVV + ECI, then the client can proceed with authorisation.
     */
    public function callback(ThreeDSCallbackRequest $request): JsonResponse
    {
        $result = $this->threeDS->handleCRes($request->validated('cres'));

        return response()->json($result);
    }
}
```

## FormRequests

```php
<?php

declare(strict_types=1);

namespace App\Http\Requests\Payment;

use Illuminate\Foundation\Http\FormRequest;

final class InitiateThreeDSRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', \App\Models\Payment::class);
    }

    public function rules(): array
    {
        return [
            'payment_token'   => ['required', 'string', 'max:255'],
            'amount'          => ['required', 'integer', 'min:1', 'max:99999999'],
            'currency'        => ['required', 'string', 'size:3'],
            'order_id'        => ['required', 'string', 'max:64'],
            // Browser / device data collected by 3DS.js on the client
            'browser_info'    => ['required', 'array'],
            'browser_info.accept_header'       => ['required', 'string', 'max:2048'],
            'browser_info.user_agent'          => ['required', 'string', 'max:2048'],
            'browser_info.ip_address'          => ['required', 'ip'],
            'browser_info.java_enabled'        => ['required', 'boolean'],
            'browser_info.javascript_enabled'  => ['required', 'boolean'],
            'browser_info.language'            => ['required', 'string', 'max:8'],
            'browser_info.color_depth'         => ['required', 'integer'],
            'browser_info.screen_height'       => ['required', 'integer'],
            'browser_info.screen_width'        => ['required', 'integer'],
            'browser_info.time_zone_offset'    => ['required', 'integer'],
        ];
    }
}

final class ThreeDSCallbackRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // ACS does not send auth header; validate shared secret in service
    }

    public function rules(): array
    {
        return [
            // CRes is a base64url-encoded JSON object from ACS
            'cres' => ['required', 'string'],
        ];
    }
}
```

## ThreeDSService

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Exceptions\ThreeDSHardDeclineException;
use App\Exceptions\ThreeDSUnavailableException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

final class ThreeDSService
{
    /**
     * Initiate 3DS2 authentication by sending an AReq to the 3DS server.
     *
     * transStatus values:
     *   Y = authenticated (frictionless)
     *   A = attempted (frictionless, partial liability shift)
     *   C = challenge required — return acsUrl to client for redirect
     *   N = not authenticated — hard decline, do not proceed
     *   R = rejected — hard decline, do not proceed
     *   U = unavailable — fall back to 3DS1
     */
    public function initiate(array $data): array
    {
        $areqPayload = [
            'messageType'         => 'AReq',
            'messageVersion'      => '2.2.0',
            'merchantId'          => config('payment.merchant_id'),
            'merchantName'        => config('payment.merchant_name'),
            'purchaseAmount'      => $data['amount'],
            'purchaseCurrency'    => $data['currency'],
            'purchaseExponent'    => 2,
            'purchaseDate'        => now()->format('YmdHis'),
            'transType'           => '01',
            'paymentToken'        => $data['payment_token'],
            'browserInformation'  => $data['browser_info'],
            'notificationUrl'     => route('payments.3ds.callback'),
            'threeDSRequestorId'  => config('payment.3ds_requestor_id'),
            'threeDSRequestorURL' => config('app.url'),
        ];

        $response = Http::withOptions(['verify' => config('payment.ca_bundle')])
            ->timeout(10)
            ->withToken(config('payment.3ds_server_api_key'))
            ->post(config('payment.3ds_server_url') . '/areq', $areqPayload);

        $body = $response->json();
        $transStatus = $body['transStatus'] ?? 'U';

        Log::info('3ds.areq.response', [
            'order_id'    => $data['order_id'],
            'transStatus' => $transStatus,
            'dsTransId'   => $body['dsTransID'] ?? null,
            'eci'         => $body['eci'] ?? null,
        ]);

        // Hard declines — never proceed to authorisation
        if (in_array($transStatus, ['N', 'R'], strict: true)) {
            throw new ThreeDSHardDeclineException(
                transStatus: $transStatus,
                dsTransId: $body['dsTransID'] ?? null,
            );
        }

        // 3DS server unavailable — caller should retry with 3DS1
        if ($transStatus === 'U') {
            throw new ThreeDSUnavailableException(orderId: $data['order_id']);
        }

        // Frictionless — authentication complete, return values for authorisation
        if (in_array($transStatus, ['Y', 'A'], strict: true)) {
            return [
                'status'      => 'authenticated',
                'cavv'        => $body['authenticationValue'],   // 28-char base64
                'eci'         => $body['eci'],
                'dsTransId'   => $body['dsTransID'],
                'acsTransId'  => $body['acsTransID'],
                'transStatus' => $transStatus,
            ];
        }

        // Challenge required — return ACS redirect details to client
        // Client must redirect cardholder to $acsUrl with encoded creqToken
        return [
            'status'              => 'challenge_required',
            'acsUrl'              => $body['acsURL'],
            'creqToken'           => $body['creqToken'],      // base64url-encoded CReq
            'threeDSSessionData'  => $body['threeDSSessionData'],
            'acsTransId'          => $body['acsTransID'],
            'dsTransId'           => $body['dsTransID'],
        ];
    }

    /**
     * Handle the CRes posted back by ACS after challenge completion.
     *
     * CRes is a base64url-encoded JSON object. Decode, validate transStatus,
     * extract CAVV and ECI for the authorisation request.
     */
    public function handleCRes(string $cresEncoded): array
    {
        // Decode base64url → JSON
        $cresJson = base64_decode(strtr($cresEncoded, '-_', '+/'));
        $cres = json_decode($cresJson, true, 512, JSON_THROW_ON_ERROR);

        $transStatus = $cres['transStatus'] ?? 'U';

        Log::info('3ds.cres.received', [
            'transStatus' => $transStatus,
            'acsTransId'  => $cres['acsTransID'] ?? null,
            'dsTransId'   => $cres['dsTransID'] ?? null,
        ]);

        // Hard declines from ACS challenge result — do not proceed
        if (in_array($transStatus, ['N', 'R'], strict: true)) {
            throw new ThreeDSHardDeclineException(
                transStatus: $transStatus,
                dsTransId: $cres['dsTransID'] ?? null,
            );
        }

        if ($transStatus === 'U') {
            throw new ThreeDSUnavailableException(orderId: $cres['threeDSServerTransID'] ?? 'unknown');
        }

        // Fetch full authentication result from 3DS server (CRes only has partial data)
        $authResult = $this->fetchAuthResult($cres['threeDSServerTransID']);

        return [
            'status'      => 'authenticated',
            'cavv'        => $authResult['authenticationValue'],
            'eci'         => $authResult['eci'],
            'dsTransId'   => $cres['dsTransID'],
            'acsTransId'  => $cres['acsTransID'],
            'transStatus' => $transStatus,
        ];
    }

    private function fetchAuthResult(string $threeDSServerTransId): array
    {
        $response = Http::withOptions(['verify' => config('payment.ca_bundle')])
            ->timeout(10)
            ->withToken(config('payment.3ds_server_api_key'))
            ->get(config('payment.3ds_server_url') . '/results/' . $threeDSServerTransId);

        return $response->json();
    }
}
```

## Exceptions

```php
<?php

declare(strict_types=1);

namespace App\Exceptions;

final class ThreeDSHardDeclineException extends \RuntimeException
{
    public function __construct(
        public readonly string $transStatus,
        public readonly ?string $dsTransId,
    ) {
        parent::__construct("3DS hard decline: transStatus={$transStatus}");
    }
}

final class ThreeDSUnavailableException extends \RuntimeException
{
    public function __construct(public readonly string $orderId)
    {
        parent::__construct("3DS server unavailable for order {$orderId}");
    }
}
```

## Test — Http::fake() Covering All transStatus Branches

```php
<?php

declare(strict_types=1);

namespace Tests\Feature\ThreeDS;

use App\Exceptions\ThreeDSHardDeclineException;
use App\Exceptions\ThreeDSUnavailableException;
use App\Services\ThreeDSService;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

final class ThreeDSChallengeFlowTest extends TestCase
{
    private array $baseData;

    protected function setUp(): void
    {
        parent::setUp();

        $this->baseData = [
            'payment_token' => 'tok_test_visa_4111',
            'amount'        => 10000,
            'currency'      => 'MYR',
            'order_id'      => 'order-abc-123',
            'browser_info'  => [
                'accept_header'      => 'application/json',
                'user_agent'         => 'Mozilla/5.0',
                'ip_address'         => '203.0.113.1',
                'java_enabled'       => false,
                'javascript_enabled' => true,
                'language'           => 'en-MY',
                'color_depth'        => 24,
                'screen_height'      => 900,
                'screen_width'       => 1440,
                'time_zone_offset'   => -480,
            ],
        ];
    }

    /** @test */
    public function it_returns_authenticated_on_frictionless_y(): void
    {
        Http::fake([
            '*/areq' => Http::response([
                'transStatus'       => 'Y',
                'eci'               => '05',
                'authenticationValue' => base64_encode(str_repeat('x', 20)), // 28 chars base64
                'dsTransID'         => 'ds-trans-001',
                'acsTransID'        => 'acs-trans-001',
            ]),
        ]);

        $result = app(ThreeDSService::class)->initiate($this->baseData);

        $this->assertEquals('authenticated', $result['status']);
        $this->assertEquals('05', $result['eci']);
        $this->assertNotEmpty($result['cavv']);
    }

    /** @test */
    public function it_returns_challenge_required_on_trans_status_c(): void
    {
        Http::fake([
            '*/areq' => Http::response([
                'transStatus'        => 'C',
                'acsURL'             => 'https://acs.issuer.example.com/challenge',
                'creqToken'          => base64_encode('{"messageType":"CReq"}'),
                'threeDSSessionData' => 'session-data-opaque',
                'acsTransID'         => 'acs-trans-002',
                'dsTransID'          => 'ds-trans-002',
            ]),
        ]);

        $result = app(ThreeDSService::class)->initiate($this->baseData);

        $this->assertEquals('challenge_required', $result['status']);
        $this->assertEquals('https://acs.issuer.example.com/challenge', $result['acsUrl']);
        $this->assertNotEmpty($result['creqToken']);
    }

    /** @test */
    public function it_throws_hard_decline_on_trans_status_n(): void
    {
        Http::fake([
            '*/areq' => Http::response([
                'transStatus' => 'N',
                'dsTransID'   => 'ds-trans-003',
            ]),
        ]);

        $this->expectException(ThreeDSHardDeclineException::class);
        $this->expectExceptionMessage('transStatus=N');

        app(ThreeDSService::class)->initiate($this->baseData);
    }

    /** @test */
    public function it_throws_hard_decline_on_trans_status_r(): void
    {
        Http::fake([
            '*/areq' => Http::response([
                'transStatus' => 'R',
                'dsTransID'   => 'ds-trans-004',
            ]),
        ]);

        $this->expectException(ThreeDSHardDeclineException::class);

        app(ThreeDSService::class)->initiate($this->baseData);
    }

    /** @test */
    public function it_throws_unavailable_on_trans_status_u(): void
    {
        Http::fake([
            '*/areq' => Http::response(['transStatus' => 'U']),
        ]);

        $this->expectException(ThreeDSUnavailableException::class);

        app(ThreeDSService::class)->initiate($this->baseData);
    }

    /** @test */
    public function it_handles_cres_callback_with_authenticated_result(): void
    {
        $cresPayload = [
            'transStatus'          => 'Y',
            'acsTransID'           => 'acs-trans-005',
            'dsTransID'            => 'ds-trans-005',
            'threeDSServerTransID' => '3ds-server-trans-005',
            'messageType'          => 'CRes',
            'messageVersion'       => '2.2.0',
        ];
        $cresEncoded = base64_encode(json_encode($cresPayload));

        Http::fake([
            '*/results/*' => Http::response([
                'authenticationValue' => base64_encode(str_repeat('y', 20)),
                'eci'                 => '05',
            ]),
        ]);

        $result = app(ThreeDSService::class)->handleCRes($cresEncoded);

        $this->assertEquals('authenticated', $result['status']);
        $this->assertEquals('05', $result['eci']);
        $this->assertNotEmpty($result['cavv']);
    }

    /** @test */
    public function it_throws_hard_decline_on_cres_with_trans_status_n(): void
    {
        $cresPayload = [
            'transStatus' => 'N',
            'dsTransID'   => 'ds-trans-006',
        ];
        $cresEncoded = base64_encode(json_encode($cresPayload));

        $this->expectException(ThreeDSHardDeclineException::class);

        app(ThreeDSService::class)->handleCRes($cresEncoded);
    }
}
```

## Key Rules

- Never proceed to authorisation if `transStatus` is `N` or `R` — these are hard declines from either the frictionless flow or the challenge result.
- CAVV is a 28-character base64 value. Pass it verbatim to the authorisation request in DE 55 or as a dedicated field — do not truncate or re-encode.
- ECI must accompany every authorisation that went through 3DS, even attempted (A) flows. Missing ECI = no liability shift.
- `transStatus: U` means the 3DS server could not determine authentication — fall back to 3DS1 VEReq/PAReq, not a direct authorisation.
- Challenge timeout is 10 minutes. If the ACS CRes callback has not arrived, treat the session as `transStatus: U` and fall back.
- Log `dsTransId` and `acsTransId` on every 3DS event — these are required for chargeback disputes.
- Never log raw CAVV values — treat authenticationValue as sensitive credential data.
