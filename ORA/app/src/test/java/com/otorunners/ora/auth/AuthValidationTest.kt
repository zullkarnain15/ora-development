package com.otorunners.ora.auth

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthValidationTest {
    @Test
    fun fourDigitPin_isValid() {
        assertTrue(isValidPin("1234"))
    }

    @Test
    fun pinShorterThanFourDigits_isInvalid() {
        assertFalse(isValidPin("123"))
    }

    @Test
    fun pinLongerThanFourDigits_isInvalid() {
        assertFalse(isValidPin("12345"))
    }

    @Test
    fun nonNumericPin_isInvalid() {
        assertFalse(isValidPin("12A4"))
    }

    @Test
    fun eightCharacterNickname_isValid() {
        assertTrue(isValidNickname("RUNNER78"))
    }

    @Test
    fun nicknameLongerThanEightCharacters_isInvalid() {
        assertFalse(isValidNickname("RUNNER789"))
    }

    @Test
    fun emptyNickname_isInvalid() {
        assertFalse(isValidNickname(""))
    }

    @Test
    fun whitespaceOnlyNickname_isInvalid() {
        assertFalse(isValidNickname("   "))
    }
}
