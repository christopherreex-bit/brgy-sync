import { onRequest as __sms_send_js_onRequest } from "/Users/aaronvincentpo/Documents/GitHub/brgy-sync/functions/sms/send.js"

export const routes = [
    {
      routePath: "/sms/send",
      mountPath: "/sms",
      method: "",
      middlewares: [],
      modules: [__sms_send_js_onRequest],
    },
  ]