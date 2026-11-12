import Foundation

/// Where the game lives online. These match the live web version, so phones
/// keep using https://buzzworthy-one.vercel.app/play exactly as before.
enum Config {
    static let supabaseURL = "https://uhpphvfudghdngrbctsz.supabase.co"
    static let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHBodmZ1ZGdoZG5ncmJjdHN6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1OTYzNjEsImV4cCI6MjEwOTE3MjM2MX0.NUvI6uYz3H_0BMkwnrMwazYjvJp3g-y1LPlRvBmRdtw"

    /// Phones scan a QR code for this address (the room code is added on the end).
    static let joinSite = "buzzworthy-one.vercel.app"
    static func joinURL(room: String) -> String { "https://\(joinSite)/play?room=\(room)" }

    /// Question packs bundled in the app (files in the Questions folder).
    static let packIDs = ["default", "general", "movies", "nineties", "sports"]
}
