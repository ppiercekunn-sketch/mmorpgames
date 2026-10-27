<?php

namespace App\Http\Resources;

use App\Models\Character;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Character
 */
class CharacterResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'class' => $this->class,
            'birth_sign' => $this->birth_sign,
            'level' => $this->level,
            'xp' => $this->xp,
            'gold' => $this->gold,
            'created_at' => $this->created_at?->utc()->format('Y-m-d\TH:i:s\Z'),
        ];
    }
}
