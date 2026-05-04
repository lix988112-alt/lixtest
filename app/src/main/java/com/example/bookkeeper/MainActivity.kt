package com.example.bookkeeper

import android.content.SharedPreferences
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.example.bookkeeper.databinding.ActivityMainBinding
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var prefs: SharedPreferences
    private val records = mutableListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        prefs = getSharedPreferences("bookkeeper", MODE_PRIVATE)
        loadRecords()

        binding.btnAdd.setOnClickListener {
            addRecord()
        }
    }

    private fun addRecord() {
        val amountText = binding.etAmount.text.toString().trim()
        val category = binding.etCategory.text.toString().trim().ifEmpty { "其他" }
        val note = binding.etNote.text.toString().trim()

        val amount = amountText.toDoubleOrNull()
        if (amount == null || amount <= 0) {
            Toast.makeText(this, "请输入正确金额", Toast.LENGTH_SHORT).show()
            return
        }

        val isExpense = binding.rgType.checkedRadioButtonId == binding.rbExpense.id
        val type = if (isExpense) "支出" else "收入"
        val signedAmount = if (isExpense) -amount else amount

        val time = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date())
        val line = "$time | $type | $category | ${"%.2f".format(amount)}元 | $note"
        records.add(0, line)

        saveRecords()
        renderRecords()

        binding.etAmount.text?.clear()
        binding.etCategory.text?.clear()
        binding.etNote.text?.clear()

        Toast.makeText(this, "已添加", Toast.LENGTH_SHORT).show()
    }

    private fun saveRecords() {
        val joined = records.joinToString("\n")
        prefs.edit().putString("records", joined).apply()
    }

    private fun loadRecords() {
        val raw = prefs.getString("records", "") ?: ""
        records.clear()
        if (raw.isNotEmpty()) {
            records.addAll(raw.split("\n"))
        }
        renderRecords()
    }

    private fun renderRecords() {
        val adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, records)
        binding.listRecords.adapter = adapter

        var income = 0.0
        var expense = 0.0
        records.forEach { line ->
            val parts = line.split("|").map { it.trim() }
            if (parts.size >= 4) {
                val type = parts[1]
                val amount = parts[3].replace("元", "").toDoubleOrNull() ?: 0.0
                if (type == "收入") income += amount else expense += amount
            }
        }

        binding.tvSummary.text = "总收入: %.2f 元    总支出: %.2f 元    结余: %.2f 元".format(income, expense, income - expense)
    }
}
