<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    private function registerPayload(array $overrides = []): array
    {
        return array_merge([
            'username' => 'alice',
            'email' => 'alice@example.com',
            'password' => 'secret123',
            'password_confirmation' => 'secret123',
        ], $overrides);
    }

    public function test_register_creates_account_and_returns_token(): void
    {
        $response = $this->postJson('/api/auth/register', $this->registerPayload());

        $response->assertCreated()
            ->assertJsonStructure(['token', 'account' => ['id', 'username', 'email']])
            ->assertJsonPath('account.username', 'alice')
            ->assertJsonPath('account.email', 'alice@example.com');

        $this->assertSame(['token', 'account'], array_keys($response->json()));
        $this->assertSame(['id', 'username', 'email'], array_keys($response->json('account')));
        $this->assertDatabaseHas('users', ['username' => 'alice', 'email' => 'alice@example.com']);

        $this->withToken($response->json('token'))
            ->getJson('/api/me')
            ->assertOk()
            ->assertJsonPath('account.username', 'alice');
    }

    public function test_register_validates_input(): void
    {
        $this->postJson('/api/auth/register', [
            'username' => 'a!',
            'email' => 'not-an-email',
            'password' => 'short',
            'password_confirmation' => 'different',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['username', 'email', 'password']);

        $this->postJson('/api/auth/register', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['username', 'email', 'password']);

        $this->postJson('/api/auth/register', $this->registerPayload(['username' => str_repeat('a', 21)]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['username']);

        $this->postJson('/api/auth/register', $this->registerPayload(['password_confirmation' => 'secret124']))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['password']);
    }

    public function test_register_rejects_duplicate_username_and_email(): void
    {
        User::factory()->create(['username' => 'alice', 'email' => 'alice@example.com']);

        $this->postJson('/api/auth/register', $this->registerPayload())
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['username', 'email']);
    }

    public function test_login_with_username(): void
    {
        User::factory()->create(['username' => 'alice', 'password' => 'secret123']);

        $this->postJson('/api/auth/login', ['login' => 'alice', 'password' => 'secret123'])
            ->assertOk()
            ->assertJsonStructure(['token', 'account' => ['id', 'username', 'email']])
            ->assertJsonPath('account.username', 'alice');
    }

    public function test_login_with_email(): void
    {
        User::factory()->create([
            'username' => 'alice',
            'email' => 'alice@example.com',
            'password' => 'secret123',
        ]);

        $this->postJson('/api/auth/login', ['login' => 'alice@example.com', 'password' => 'secret123'])
            ->assertOk()
            ->assertJsonPath('account.email', 'alice@example.com');
    }

    public function test_login_with_wrong_password_returns_422_on_login_field(): void
    {
        User::factory()->create(['username' => 'alice', 'password' => 'secret123']);

        $this->postJson('/api/auth/login', ['login' => 'alice', 'password' => 'wrongpass'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['login'])
            ->assertJsonMissingPath('token');

        $this->postJson('/api/auth/login', ['login' => 'nobody', 'password' => 'secret123'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['login']);
    }

    public function test_logout_revokes_current_token(): void
    {
        User::factory()->create(['username' => 'alice', 'password' => 'secret123']);
        $token = $this->postJson('/api/auth/login', ['login' => 'alice', 'password' => 'secret123'])
            ->json('token');

        $this->withToken($token)->postJson('/api/auth/logout')->assertNoContent();

        $this->assertDatabaseCount('personal_access_tokens', 0);

        // Reset the auth guard's cached user so the next request re-authenticates.
        $this->app['auth']->forgetGuards();

        $this->withToken($token)->getJson('/api/me')->assertUnauthorized();
    }

    public function test_me_requires_authentication(): void
    {
        $this->getJson('/api/me')
            ->assertUnauthorized()
            ->assertExactJson(['message' => 'Unauthenticated.']);

        $this->postJson('/api/auth/logout')->assertUnauthorized();
    }

    public function test_unauthenticated_request_without_accept_header_still_gets_json(): void
    {
        $this->get('/api/me')
            ->assertUnauthorized()
            ->assertExactJson(['message' => 'Unauthenticated.']);
    }

    public function test_auth_routes_are_rate_limited(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $this->postJson('/api/auth/login', ['login' => 'nobody', 'password' => 'x'])
                ->assertUnprocessable();
        }

        $this->postJson('/api/auth/login', ['login' => 'nobody', 'password' => 'x'])
            ->assertTooManyRequests();
    }

    public function test_cors_headers_are_sent_for_api_routes(): void
    {
        $this->withHeaders(['Origin' => 'http://localhost:8060'])
            ->getJson('/api/me')
            ->assertHeader('Access-Control-Allow-Origin', '*');
    }
}
