package com.espitman.mirook.reader.data

sealed class MirookBookError(message: String) : Exception(message) {
    data object MissingManifest : MirookBookError("This file is not a valid Mirook book.")
    data object MissingSource : MirookBookError("The embedded source book is missing.")
    data object PasswordRequired : MirookBookError("This book is password protected.")
    data object InvalidPassword : MirookBookError("Password is incorrect.")
    data object CryptoFailure : MirookBookError("Could not decrypt this book.")
    data class OpenFailed(val reason: String) : MirookBookError(reason)
}
