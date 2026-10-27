<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterRequest;
use App\Http\Resources\AccountResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function register(RegisterRequest $request): JsonResponse
    {
        $user = User::create($request->validated());

        return $this->tokenResponse($user, 201);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $login = $request->string('login')->toString();
        $field = filter_var($login, FILTER_VALIDATE_EMAIL) ? 'email' : 'username';

        $user = User::where($field, $login)->first();

        if (! $user || ! Hash::check($request->string('password')->toString(), $user->password)) {
            throw ValidationException::withMessages([
                'login' => [__('auth.failed')],
            ]);
        }

        return $this->tokenResponse($user, 200);
    }

    public function logout(Request $request): Response
    {
        $request->user()->currentAccessToken()->delete();

        return response()->noContent();
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'account' => new AccountResource($request->user()),
        ]);
    }

    private function tokenResponse(User $user, int $status): JsonResponse
    {
        $token = $user->createToken('game-client')->plainTextToken;

        return response()->json([
            'token' => $token,
            'account' => new AccountResource($user),
        ], $status);
    }
}
