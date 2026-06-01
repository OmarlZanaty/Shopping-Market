import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../stores/authStore';
import toast from 'react-hot-toast';

export default function LoginPage() {
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const { login } = useAuthStore();
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await login(phone, password);
      navigate('/dashboard');
      toast.success('Welcome back!');
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#1A1A2E] to-[#2D2D44] flex items-center justify-center p-4">
      <div className="bg-white rounded-3xl p-8 w-full max-w-sm shadow-2xl">
        <div className="text-center mb-8">
          <div className="w-20 h-20 rounded-2xl mx-auto mb-4 shadow-lg overflow-hidden bg-[#1A1A2E] flex items-center justify-center">
            <img src="/logo.png" alt="Shopping Market" className="w-full h-full object-contain" />
          </div>
          <h1 className="text-2xl font-bold text-[#1A1A2E] font-serif">Shopping Market</h1>
          <p className="text-gray-500 text-sm mt-1">Admin Dashboard</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">Phone Number</label>
            <input value={phone} onChange={e => setPhone(e.target.value)} type="text"
              placeholder="01000000000" required
              className="w-full border-2 border-gray-100 focus:border-[#FF8C00] rounded-xl px-4 py-3 outline-none text-sm transition-colors"
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">Password</label>
            <input value={password} onChange={e => setPassword(e.target.value)} type="password"
              placeholder="••••••" required
              className="w-full border-2 border-gray-100 focus:border-[#FF8C00] rounded-xl px-4 py-3 outline-none text-sm transition-colors"
            />
          </div>
          <button type="submit" disabled={loading}
            className="w-full bg-gradient-to-r from-[#FF8C00] to-[#FF6B00] hover:opacity-90 text-white py-3.5 rounded-xl font-bold text-sm transition-opacity disabled:opacity-60 mt-2 shadow-lg">
            {loading ? '...' : 'Login to Admin Panel'}
          </button>
        </form>
        <p className="text-center text-xs text-gray-400 mt-6">Shopping Market Admin v1.0</p>
      </div>
    </div>
  );
}
