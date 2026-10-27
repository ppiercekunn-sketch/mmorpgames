<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CharacterController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::middleware('throttle:auth')->group(function () {
        Route::post('register', [AuthController::class, 'register']);
        Route::post('login', [AuthController::class, 'login']);
    });

    Route::post('logout', [AuthController::class, 'logout'])->middleware('auth:sanctum');
});

Route::middleware('auth:sanctum')->group(function () {
    Route::get('me', [AuthController::class, 'me']);

    Route::get('characters', [CharacterController::class, 'index']);
    Route::post('characters', [CharacterController::class, 'store']);
    Route::get('characters/{id}', [CharacterController::class, 'show'])->whereNumber('id');
    Route::delete('characters/{id}', [CharacterController::class, 'destroy'])->whereNumber('id');
});
