<?php

namespace App\Models;

use Database\Factories\CharacterFactory;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class Character extends Model
{
    /** @use HasFactory<CharacterFactory> */
    use HasFactory;

    /**
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'class',
        'birth_sign',
    ];

    /**
     * @var array<string, mixed>
     */
    protected $attributes = [
        'class' => 'warrior',
        'level' => 1,
        'xp' => 0,
        'gold' => 0,
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'level' => 'integer',
            'xp' => 'integer',
            'gold' => 'integer',
        ];
    }

    /**
     * Setting the name also sets `name_key`, the case-insensitive uniqueness key.
     */
    protected function name(): Attribute
    {
        return Attribute::make(
            set: fn (string $value) => [
                'name' => $value,
                'name_key' => self::nameKey($value),
            ],
        );
    }

    public static function nameKey(string $name): string
    {
        return Str::lower($name);
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
