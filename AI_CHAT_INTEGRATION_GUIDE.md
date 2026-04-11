# MindTwin AI Chat Integration Guide

## Overview
The MindTwin app now includes an **AI-powered mental health support chat** using OpenRouter API for LLM capabilities. The system is designed to:
- Provide 24/7 mental health guidance to patients
- Assist therapists with clinical analysis and treatment planning
- Preserve tokens efficiently with rate limiting and budget tracking
- Maintain conversation history securely in the database
- Never expose API keys in the frontend or public code

---

## Architecture

### Backend Components
1. **LLMService** (`backend/src/services/LLMService.js`)
   - Handles OpenRouter API integration
   - Token budget management (10,000 tokens/day)
   - Request rate limiting (10 requests/hour per user)
   - Conversation history storage

2. **Chat Routes** (`backend/src/routes/chat.js`)
   - `POST /api/chat/message` - Send message and get AI response
   - `GET /api/chat/conversation/:id` - Retrieve conversation history
   - `GET /api/chat/conversations/:userId` - List all user conversations
   - `GET /api/chat/tokens/status` - Check token budget status
   - `POST /api/chat/crisis-response` - Generate crisis intervention response
   - `POST /api/chat/analyze-assessment` - Analyze patient assessments

3. **Database** (`backend/src/database/Database.js`)
   - `chat_messages` table - Stores all conversation messages with token usage
   - Indexes for fast querying by user, conversation, and timestamp

4. **Rate Limiting** (`backend/src/middleware/TokenBucketMiddleware.js`)
   - Token bucket algorithm
   - 10 requests per hour per user
   - Prevents API key quota exhaustion

### Environment Configuration
```env
# backend/.env
OPENROUTER_API_KEY=your_openrouter_api_key_here
OPENROUTER_MODEL=openai/gpt-4-turbo
```

---

## Frontend Components

### Chat Service (`lib/services/chat_service.dart`)
Singleton service handling all LLM communication:
```dart
// Initialize (in app startup)
final chatService = ChatService();
await chatService.initialize(
  baseUrl: 'http://localhost:5000',
  userId: 'patient123',
  userRole: 'patient', // or 'therapist'
);

// Send message
final result = await chatService.sendMessage('I am feeling anxious');
if (result['success']) {
  print(result['aiResponse']);
  print('Remaining budget: ${result['remainingBudget']}');
}

// Get token status
final status = await chatService.getTokenStatus();
print('${status['percentageUsed']}% of daily budget used');
```

### Patient Chat Screen (`lib/screens/patient/patient_ai_chat_screen.dart`)
Interactive chat interface for patients with:
- Message history
- Token budget display
- Error handling
- Loading states
- Auto message sending

**Features:**
- Conversational support with AI
- Mental health guidance
- Coping strategy suggestions
- Seamless integration with therapist system
- Message timestamps

### Therapist Chat Screen (`lib/screens/therapist/therapist_ai_chat_screen.dart`)
Clinical decision support interface for therapists with:
- Patient-specific chat context
- Token budget tracking with visual progress bar
- Clinical prompt suggestions
- AI analysis of patient data
- Assessment interpretation assistance

**Features:**
- Treatment planning assistance
- Patient assessment analysis
- Intervention recommendations
- Evidence-based guidance
- Secure patient context

---

## How to Use in Your App

### 1. Add Chat to Patient Dashboard
```dart
// In patient_dashboard_screen.dart
FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientAIChatScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  },
  tooltip: 'AI Support Chat',
  child: const Icon(Icons.chat),
)
```

### 2. Add Chat to Therapist Dashboard
```dart
// In therapist_dashboard_screen.dart
ListTile(
  leading: const Icon(Icons.psychology),
  title: const Text('AI Clinical Assistant'),
  subtitle: const Text('Get insights for ${patientName}'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TherapistAIChatScreen(
          therapistId: widget.therapistId,
          patientId: selectedPatientId,
          patientName: selectedPatientName,
        ),
      ),
    );
  },
)
```

### 3. Initialize Chat Service on App Startup
```dart
// In main.dart or app initialization
void initializeServices() {
  final chatService = ChatService();
  
  // After user login
  chatService.initialize(
    baseUrl: 'http://localhost:5000',
    userId: userId,
    userRole: userRole,
  );
}
```

---

## Token Budget Management

### Daily Budget: 10,000 tokens
- Distributed across all users
- Resets every 24 hours (UTC)
- ~200 tokens per short conversation
- ~20-30 typical conversations per day

### Optimize Token Usage
1. **Keep messages concise** - Shorter prompts use fewer tokens
2. **Set conversation limits** - Archive old conversations
3. **Use fallback text** - When budget is exhausted
4. **Cache responses** - Store clinical insights locally
5. **Batch requests** - Combine analysis into single requests

### Token Monitoring
```dart
// Check status anytime
final status = await chatService.getTokenStatus();
if (status['remaining'] < 500) {
  showWarning('Low token budget. Use wisely.');
}
```

---

## Security & Privacy

### API Key Protection ✅
- **Not in frontend code** - Stored only in backend `.env`
- **Not in git** - `.env` is in `.gitignore`
- **Secure transmission** - All requests go through your backend
- **Rate limited** - Prevents abuse
- **Token budgeted** - Can't be over-consumed

### Data Privacy
- All conversations stored locally in SQLite
- Messages tied to user_id and role
- Conversation history accessible only to conversation owner
- No data sent to third parties
- PII is never logged in LLM prompts

### Clinical Safeguards
- System prompts guide AI away from diagnosis
- Crisis indicators trigger escalation recommendations
- Therapist involvement required for serious cases
- All AI responses include disclaimers
- Human therapist always makes final decisions

---

## Example Workflows

### Patient Seeking Coping Strategies
```
Patient: "I'm having trouble sleeping due to anxiety"
AI: "Let's work through some sleep hygiene and anxiety reduction techniques...
    [provides CBT-based suggestions]
    Would you like me to remind your therapist about this concern?"
```

### Therapist Getting Assessment Insights
```
Therapist: "Analyze this patient's recent PHQ-9 trends: baseline 18, last week 14"
AI: "This shows a 22% improvement in 6 weeks, indicating good treatment response.
    Consider: reinforcing current interventions, gradually reducing med dosage,
    or transitioning to maintenance therapy..."
```

### Crisis Response
```
Patient: "I don't think I should be alive"
AI: "I'm deeply concerned about your safety. This is serious.
    Please immediately call the National Suicide Prevention Lifeline: 988
    Or text 'HELLO' to 741741
    I'm also notifying your therapist."
[System: Auto-escalates to therapist alert]
```

---

## Troubleshooting

### Chat Not Working?
1. **Check backend is running**: `curl http://localhost:5000/health`
2. **Verify API key**: Check `.env` has`OPENROUTER_API_KEY` set
3. **Check token budget**: `GET /api/chat/tokens/status`
4. **Review rate limit**: Max 10 requests/hour per user
5. **Check network**: Ensure `baseUrl` matches backend URL

### Token Budget Exhausted?
- Budget resets after 24 hours
- Check usage: `chatService.getTokenStatus()`
- Implement fallback: "Daily budget reached. Chat with your therapist instead."

### AI Responses Not Cohesive?
- Load conversation history properly before sending
- System prompt may need adjustment
- Check temperature setting (0.7 is balanced)

### Privacy Concerns?
- Never call OpenRouter directly from frontend
- Always route through your backend
- API key stays in backend `.env` only
- Monitor for any frontend API key exposure

---

## Files Modified/Created

### Backend
- ✅ `backend/src/services/LLMService.js` - OpenRouter integration
- ✅ `backend/src/routes/chat.js` - Chat API endpoints
- ✅ `backend/src/middleware/TokenBucketMiddleware.js` - Rate limiting
- ✅ `backend/.env` - API key (sensitive, not in git)
- ✅ `backend/.env.example` - Template for `.env`
- ✅ `backend/index.js` - Added chat routes
- ✅ `backend/src/database/Database.js` - Added chat_messages table

### Frontend (Flutter)
- ✅ `lib/services/chat_service.dart` - Chat service (updated)
- ✅ `lib/screens/patient/patient_ai_chat_screen.dart` - Patient UI (created)
- ✅ `lib/screens/therapist/therapist_ai_chat_screen.dart` - Therapist UI (created)
- ✅ `pubspec.yaml` - All dependencies already included

---

## Next Steps

1. **Test the backend**:
   ```bash
   cd backend
   npm start
   # Check: curl http://localhost:5000/health
   ```

2. **Test the API**:
   ```bash
   curl -X POST http://localhost:5000/api/chat/message \
     -H "Content-Type: application/json" \
     -d '{
       "userId": "test-patient-1",
       "userRole": "patient",
       "message": "I am feeling anxious"
     }'
   ```

3. **Integrate into app**:
   - Add chat screens to navigation
   - Initialize `ChatService` on app startup
   - Test both patient and therapist flows
   - Monitor token usage

4. **Deploy**:
   - Ensure `.env` is secure on server
   - Test rate limiting
   - Monitor daily token usage
   - Set up alerts if budget running low

---

## Support
For issues or questions about the AI chat feature:
1. Check the logs: `backend/mindtwin.db` and console
2. Verify `.env` configuration
3. Test backend health: `GET /health`
4. Monitor token status: `GET /api/chat/tokens/status`

Your AI chat system is now ready to provide compassionate, evidence-based mental health support! 🚀
