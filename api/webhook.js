
export default function handler(req, res) {
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (
      mode === "subscribe" &&
      token &&
      token === process.env.WHATSAPP_VERIFY_TOKEN &&
      challenge
    ) {
      return res.status(200).send(challenge);
    }

    return res.status(403).send("Verification failed");
  }

  if (req.method === "POST") {
    // Receção inicial dos eventos do WhatsApp.
    // A validação da assinatura será adicionada
    // antes de processar eventos em produção.
    return res.status(200).send("EVENT_RECEIVED");
  }

  res.setHeader("Allow", "GET, POST");
  return res.status(405).send("Method not allowed");
}
