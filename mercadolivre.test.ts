// jest types
/**
 * @jest-environment node
 */
import { MercadoLivre } from './mercadolivre';

describe('MercadoLivre API', () => {
  it('should get user info and print the response', async () => {
    // Use a secret name (adjust as needed)
    const secretName = process.env.ML_SECRET_NAME || 'mercadolivre-credentials';
    const ml = new MercadoLivre(secretName);
    const response = await ml.getUser();
    console.log('getUser response:', response);
    expect(response).toHaveProperty('data');
    expect(response.status).toBe(200);
  });
}); 