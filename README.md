# MercadoLivre Lambda Integration

This project provides an integration with the Mercado Livre APIs, designed for use in AWS Lambda environments. It securely manages API credentials using AWS Secrets Manager and offers a TypeScript class for interacting with Mercado Livre endpoints.

## Features
- Securely loads and refreshes Mercado Livre API tokens using AWS Secrets Manager
- Generic methods for GET, POST, PUT, DELETE requests
- Helper methods for common Mercado Livre operations (get user, items, orders, etc.)
- Written in TypeScript
- Ready for deployment in AWS Lambda

## Requirements
- Node.js >= 16
- AWS account with access to Secrets Manager
- Mercado Livre developer credentials

## Setup
1. **Install dependencies:**
   ```bash
   npm install
   ```
2. **Configure AWS credentials:**
   Ensure your environment has AWS credentials with permission to access the required secret in AWS Secrets Manager.

3. **Create a secret in AWS Secrets Manager:**
   The secret should be a JSON object with the following fields:
   ```json
   {
     "client_id": "YOUR_ML_CLIENT_ID",
     "client_secret": "YOUR_ML_CLIENT_SECRET",
     "refresh_token": "YOUR_ML_REFRESH_TOKEN"
   }
   ```
   The default secret name is `mercadolivre-credentials`, but you can override it with the `ML_SECRET_NAME` environment variable.

## Build
To compile the TypeScript code:
```bash
npm run build
```

## Lint
To check code style:
```bash
npm run lint
```

## Test
To run tests (requires a valid secret in AWS Secrets Manager):
```bash
npm test
```

## Usage Example
You can use the `MercadoLivre` class in your code as follows:
```typescript
import { MercadoLivre } from './mercadolivre';

const secretName = process.env.ML_SECRET_NAME || 'mercadolivre-credentials';
const ml = new MercadoLivre(secretName);

(async () => {
  const user = await ml.getUser();
  console.log(user);
})();
```

## License
MIT 