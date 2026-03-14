//
//  Supabase.swift
//  PathRecorder
//
//  Created by Aparna Natarajan on 3/14/26.
//


import Supabase
import SwiftUI

let supabase = SupabaseClient(
  supabaseURL: URL(string: "https://hsbnabtalqugbwspdhnq.supabase.co")!,
  supabaseKey: "sb_publishable_plix2vRBUgoocyW2QacrVA_tqPYIO-M"
)

@MainActor
final class AuthManager: ObservableObject {
  @Published var currentUser: User?
  @Published var isLoadingSession = true

  private var authListenerTask: Task<Void, Never>?

  var isAuthenticated: Bool {
    currentUser != nil
  }

  init() {
    authListenerTask = Task {
      for await (_, session) in await supabase.auth.authStateChanges {
        self.currentUser = session?.user
        self.isLoadingSession = false
      }
    }

    Task {
      await restoreSession()
    }
  }

  deinit {
    authListenerTask?.cancel()
  }

  func restoreSession() async {
    do {
      let session = try await supabase.auth.session
      currentUser = session.user
    } catch {
      currentUser = nil
    }
    isLoadingSession = false
  }

  /// Sends an SMS OTP. Creates the user if they don't exist yet, so this
  /// doubles as both sign-in and sign-up.
  func requestOTP(phone: String) async throws {
    let normalizedPhone = normalized(phone: phone)
    guard !normalizedPhone.isEmpty else {
      throw AuthFlowError.invalidPhone
    }

    try await supabase.auth.signInWithOTP(
      phone: normalizedPhone,
      shouldCreateUser: true
    )
  }

  func verifyOTP(phone: String, token: String) async throws {
    let normalizedPhone = normalized(phone: phone)
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalizedPhone.isEmpty else {
      throw AuthFlowError.invalidPhone
    }

    guard !normalizedToken.isEmpty else {
      throw AuthFlowError.invalidOTP
    }

    _ = try await supabase.auth.verifyOTP(
      phone: normalizedPhone,
      token: normalizedToken,
      type: .sms
    )
  }

  func signOut() async throws {
    try await supabase.auth.signOut()
    currentUser = nil
  }

  func displayPhone(for user: User?) -> String {
    user?.phone ?? "Unknown"
  }

  private func normalized(phone: String) -> String {
    phone
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")
  }
}

enum AuthFlowError: LocalizedError {
  case invalidPhone
  case invalidOTP

  var errorDescription: String? {
    switch self {
    case .invalidPhone:
      return "Enter a valid phone number in E.164 format (example: +15551234567)."
    case .invalidOTP:
      return "Enter the OTP code sent to your phone."
    }
  }
}


