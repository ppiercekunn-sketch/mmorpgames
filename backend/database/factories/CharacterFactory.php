<?php

namespace Database\Factories;

use App\Models\Character;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Character>
 */
class CharacterFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'name' => fake()->unique()->regexify('[A-Z][a-z]{5}[0-9]{3}'),
            'class' => config('game.default_class'),
            'birth_sign' => fake()->randomElement(config('game.birth_signs')),
        ];
    }
}
