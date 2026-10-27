<?php

namespace Tests\Feature;

use App\Models\Character;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CharacterTest extends TestCase
{
    use RefreshDatabase;

    private function actingAsUser(): User
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        return $user;
    }

    public function test_character_routes_require_authentication(): void
    {
        $this->getJson('/api/characters')->assertUnauthorized();
        $this->postJson('/api/characters', ['name' => 'Aldric', 'birth_sign' => 'aries'])->assertUnauthorized();
        $this->getJson('/api/characters/1')->assertUnauthorized();
        $this->deleteJson('/api/characters/1')->assertUnauthorized();
    }

    public function test_create_character(): void
    {
        $user = $this->actingAsUser();

        $response = $this->postJson('/api/characters', ['name' => 'Aldric', 'birth_sign' => 'aries']);

        $response->assertCreated()
            ->assertJsonPath('character.name', 'Aldric')
            ->assertJsonPath('character.class', 'warrior')
            ->assertJsonPath('character.birth_sign', 'aries')
            ->assertJsonPath('character.level', 1)
            ->assertJsonPath('character.xp', 0)
            ->assertJsonPath('character.gold', 0);

        $this->assertSame(
            ['id', 'name', 'class', 'birth_sign', 'level', 'xp', 'gold', 'created_at'],
            array_keys($response->json('character')),
        );
        $this->assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/',
            $response->json('character.created_at'),
        );
        $this->assertDatabaseHas('characters', [
            'user_id' => $user->id,
            'name' => 'Aldric',
            'name_key' => 'aldric',
        ]);
    }

    public function test_class_from_request_is_ignored(): void
    {
        $this->actingAsUser();

        $this->postJson('/api/characters', ['name' => 'Aldric', 'birth_sign' => 'leo', 'class' => 'mage'])
            ->assertCreated()
            ->assertJsonPath('character.class', 'warrior');
    }

    public function test_invalid_birth_sign_is_rejected(): void
    {
        $this->actingAsUser();

        $this->postJson('/api/characters', ['name' => 'Aldric', 'birth_sign' => 'ophiuchus'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['birth_sign']);

        $this->postJson('/api/characters', ['name' => 'Aldric'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['birth_sign']);
    }

    public function test_invalid_name_is_rejected(): void
    {
        $this->actingAsUser();

        foreach (['Al', str_repeat('a', 17), 'Bad Name', 'Bad_Name', ''] as $name) {
            $this->postJson('/api/characters', ['name' => $name, 'birth_sign' => 'aries'])
                ->assertUnprocessable()
                ->assertJsonValidationErrors(['name']);
        }
    }

    public function test_duplicate_name_is_rejected_case_insensitively(): void
    {
        Character::factory()->create(['name' => 'Aldric']);
        $this->actingAsUser();

        $this->postJson('/api/characters', ['name' => 'aLDRIC', 'birth_sign' => 'aries'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name']);

        $this->assertDatabaseCount('characters', 1);
    }

    public function test_fourth_character_is_rejected(): void
    {
        $user = $this->actingAsUser();
        Character::factory()->count(3)->for($user)->create();

        $this->postJson('/api/characters', ['name' => 'Fourth', 'birth_sign' => 'aries'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name']);

        $this->assertSame(3, $user->characters()->count());
    }

    public function test_list_only_shows_own_characters(): void
    {
        $user = $this->actingAsUser();
        $mine = Character::factory()->count(2)->for($user)->create();
        Character::factory()->count(2)->create();

        $response = $this->getJson('/api/characters')->assertOk();

        $response->assertJsonCount(2, 'characters');
        $this->assertEqualsCanonicalizing(
            $mine->pluck('id')->all(),
            collect($response->json('characters'))->pluck('id')->all(),
        );
    }

    public function test_show_own_character(): void
    {
        $user = $this->actingAsUser();
        $character = Character::factory()->for($user)->create(['name' => 'Aldric', 'birth_sign' => 'virgo']);

        $this->getJson("/api/characters/{$character->id}")
            ->assertOk()
            ->assertJsonPath('character.id', $character->id)
            ->assertJsonPath('character.name', 'Aldric')
            ->assertJsonPath('character.birth_sign', 'virgo');
    }

    public function test_cannot_view_or_delete_another_users_character(): void
    {
        $this->actingAsUser();
        $other = Character::factory()->create();

        $this->getJson("/api/characters/{$other->id}")->assertNotFound();
        $this->deleteJson("/api/characters/{$other->id}")->assertNotFound();

        $this->assertModelExists($other);
    }

    public function test_missing_character_returns_404(): void
    {
        $this->actingAsUser();

        $this->getJson('/api/characters/999')->assertNotFound();
        $this->getJson('/api/characters/abc')->assertNotFound();
    }

    public function test_delete_own_character(): void
    {
        $user = $this->actingAsUser();
        $character = Character::factory()->for($user)->create();

        $this->deleteJson("/api/characters/{$character->id}")->assertNoContent();

        $this->assertModelMissing($character);
    }

    public function test_deleted_character_name_can_be_reused(): void
    {
        $user = $this->actingAsUser();
        $character = Character::factory()->for($user)->create(['name' => 'Aldric']);

        $this->deleteJson("/api/characters/{$character->id}")->assertNoContent();

        $this->postJson('/api/characters', ['name' => 'Aldric', 'birth_sign' => 'aries'])->assertCreated();
    }
}
