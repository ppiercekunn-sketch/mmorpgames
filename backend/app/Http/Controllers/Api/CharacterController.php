<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreCharacterRequest;
use App\Http\Resources\CharacterResource;
use App\Models\Character;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Validation\ValidationException;

class CharacterController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $characters = $request->user()->characters()->orderBy('id')->get();

        return response()->json([
            'characters' => CharacterResource::collection($characters),
        ]);
    }

    public function store(StoreCharacterRequest $request): JsonResponse
    {
        try {
            $character = $request->user()->characters()->create([
                'name' => $request->validated('name'),
                'birth_sign' => $request->validated('birth_sign'),
                'class' => config('game.default_class'),
            ]);
        } catch (UniqueConstraintViolationException) {
            // Lost a race with a concurrent request for the same name.
            throw ValidationException::withMessages([
                'name' => ['The name has already been taken.'],
            ]);
        }

        return response()->json([
            'character' => new CharacterResource($character->refresh()),
        ], 201);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        return response()->json([
            'character' => new CharacterResource($this->findOwned($request, $id)),
        ]);
    }

    public function destroy(Request $request, int $id): Response
    {
        $this->findOwned($request, $id)->delete();

        return response()->noContent();
    }

    /**
     * Look the character up within the caller's own characters, so other
     * accounts' characters are indistinguishable from missing ones (404).
     */
    private function findOwned(Request $request, int $id): Character
    {
        return $request->user()->characters()->findOrFail($id);
    }
}
