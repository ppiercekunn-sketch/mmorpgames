<?php

namespace App\Http\Requests;

use App\Models\Character;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class StoreCharacterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'name' => [
                'required',
                'string',
                'min:3',
                'max:16',
                'regex:/^[A-Za-z0-9]+$/',
                function (string $attribute, mixed $value, \Closure $fail) {
                    if (is_string($value) && Character::where('name_key', Character::nameKey($value))->exists()) {
                        $fail('The name has already been taken.');
                    }
                },
            ],
            'birth_sign' => ['required', 'string', Rule::in(config('game.birth_signs'))],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'name.regex' => 'The name may only contain letters and digits.',
            'birth_sign.in' => 'The selected birth sign is invalid.',
        ];
    }

    /**
     * @return array<int, callable>
     */
    public function after(): array
    {
        return [
            function (Validator $validator) {
                $max = (int) config('game.max_characters_per_account');

                if ($this->user()->characters()->count() >= $max) {
                    $validator->errors()->add('name', "You can have at most {$max} characters.");
                }
            },
        ];
    }
}
